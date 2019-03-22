"""
    HMC(n_iters::Int, epsilon::Float64, tau::Int)

Hamiltonian Monte Carlo sampler.

Arguments:

- `n_iters::Int` : The number of samples to pull.
- `epsilon::Float64` : The leapfrog step size to use.
- `tau::Int` : The number of leapfrop steps to use.

Usage:

```julia
HMC(1000, 0.05, 10)
```

Example:

```julia
# Define a simple Normal model with unknown mean and variance.
@model gdemo(x) = begin
    s ~ InverseGamma(2,3)
    m ~ Normal(0, sqrt(s))
    x[1] ~ Normal(m, sqrt(s))
    x[2] ~ Normal(m, sqrt(s))
    return s, m
end

sample(gdemo([1.5, 2]), HMC(1000, 0.05, 10))
```

Tips:

- If you are receiving gradient errors when using `HMC`, try reducing the
`step_size` parameter.

```julia
# Original step_size
sample(gdemo([1.5, 2]), HMC(1000, 0.1, 10))

# Reduced step_size.
sample(gdemo([1.5, 2]), HMC(1000, 0.01, 10))
```
"""
mutable struct HMC{AD, T} <: StaticHamiltonian{AD}
    n_iters   ::  Int       # number of samples
    epsilon   ::  Float64   # leapfrog step size
    tau       ::  Int       # leapfrog step number
    space     ::  Set{T}    # sampling space, emtpy means all
end
HMC(args...) = HMC{ADBackend()}(args...)
function HMC{AD}(epsilon::Float64, tau::Int, space...) where AD
    _space = isa(space, Symbol) ? Set([space]) : Set(space)
    return HMC{AD, eltype(_space)}(1, epsilon, tau, _space)
end
function HMC{AD}(n_iters::Int, epsilon::Float64, tau::Int) where AD
    return HMC{AD, Any}(n_iters, epsilon, tau, Set())
end
function HMC{AD}(n_iters::Int, epsilon::Float64, tau::Int, space...) where AD
    _space = isa(space, Symbol) ? Set([space]) : Set(space)
    return HMC{AD, eltype(_space)}(n_iters, epsilon, tau, _space)
end

function hmc_step(θ, lj, lj_func, grad_func, H_func, ϵ, alg::HMC, momentum_sampler::Function;
                  rev_func=nothing, log_func=nothing)
    θ_new, lj_new, is_accept, τ_valid, α = _hmc_step(
        θ, lj, lj_func, grad_func, H_func, alg.tau, ϵ, momentum_sampler; rev_func=rev_func, log_func=log_func)
    return θ_new, lj_new, HMCStats(α, is_accept, ϵ, τ_valid)
end

# Below is a trick to remove the dependency of Stan by Requires.jl
# Please see https://github.com/TuringLang/Turing.jl/pull/459 for explanations
DEFAULT_ADAPT_CONF_TYPE = Nothing
STAN_DEFAULT_ADAPT_CONF = nothing

Sampler(alg::Hamiltonian, s::Selector) =  Sampler(alg, nothing, s)
Sampler(alg::Hamiltonian, adapt_conf::Nothing) = Sampler(alg, adapt_conf, Selector())
function Sampler(alg::Hamiltonian, adapt_conf::Nothing, s::Selector)
    return _sampler(alg::Hamiltonian, adapt_conf, s)
end
function _sampler(alg::Hamiltonian, adapt_conf, s::Selector)
    info=Dict{Symbol, Any}()

    # For state infomation
    info[:lf_num] = 0
    info[:eval_num] = 0

    # Adapt configuration
    info[:adapt_conf] = adapt_conf

    Sampler(alg, info, s)
end

function sample(model::Model, alg::Hamiltonian;
                save_state=false,                   # flag for state saving
                resume_from=nothing,                # chain to continue
                reuse_spl_n=0,                      # flag for spl re-using
                pc_type=UnitPreConditioner,         # pre-conditioner type
                adapt_conf=STAN_DEFAULT_ADAPT_CONF, # adapt configuration
                )
    spl = reuse_spl_n > 0 ?
          resume_from.info[:spl] :
          Sampler(alg, adapt_conf)
    if resume_from != nothing
        spl.selector = resume_from.info[:spl].selector
    end

    @assert isa(spl.alg, Hamiltonian) "[Turing] alg type mismatch; please use resume() to re-use spl"

    alg_str = isa(alg, HMC)   ? "HMC"   :
              isa(alg, HMCDA) ? "HMCDA" :
              isa(alg, SGHMC) ? "SGHMC" :
              isa(alg, SGLD)  ? "SGLD"  :
              isa(alg, NUTS)  ? "NUTS"  : "Hamiltonian"

    # Initialization
    time_total = zero(Float64)
    n = reuse_spl_n > 0 ?
        reuse_spl_n :
        alg.n_iters
    samples = Array{Sample}(undef, n)
    weight = 1 / n
    for i = 1:n
        samples[i] = Sample(weight, Dict{Symbol, Any}())
    end

    vi = if resume_from == nothing
        vi_ = VarInfo()
        model(vi_, SampleFromUniform())
        vi_
    else
        deepcopy(resume_from.info[:vi])
    end

    if spl.selector.tag == :default
        link!(vi, spl)
        runmodel!(model, vi, spl)
    end

    # HMC steps
    accept_his = Bool[]
    PROGRESS[] && (spl.info[:progress] = ProgressMeter.Progress(n, 1, "[$alg_str] Sampling...", 0))
    local stats
    for i = 1:n
        Turing.DEBUG && @debug "$alg_str stepping..."

        time_elapsed = @elapsed vi, stats = step(model, spl, vi, Val(i == 1))
        time_total += time_elapsed

        if stats.is_accept  # accepted => store the new predcits
            samples[i].value = Sample(vi, stats; elapsed=time_elapsed).value
        else                # rejected => store the previous predcits
            samples[i] = samples[i - 1]
        end

        push!(accept_his, stats.is_accept)
        PROGRESS[] && ProgressMeter.next!(spl.info[:progress])
    end

    println("[$alg_str] Finished with")
    println("  Running time        = $time_total;")

    if resume_from != nothing   # concat samples
        pushfirst!(samples, resume_from.info[:samples]...)
    end
    c = Chain(0.0, samples)       # wrap the result by Chain

    # TODO: @Cameron we can simplify below when we have section for MCMCChain
    fns = fieldnames(typeof(stats))
    v = get(c, [:accept_ratio, :is_accept, :n_lf_steps])
    :accept_ratio in fns && println("  alpha / sample      = $(mean(v.accept_ratio));")
    :is_accept    in fns && println("  Accept rate         = $(mean(v.is_accept));")
    :n_lf_steps   in fns && println("  #lf / sample        = $(mean(v.n_lf_steps));")
    if haskey(spl.info, :wum)
      std_str = string(spl.info[:wum].pc)
      std_str = length(std_str) >= 32 ? std_str[1:30]*"..." : std_str   # only show part of pre-cond
      println("  pre-cond. metric    = $(std_str).")
    end

    if save_state               # save state
        # Convert vi back to X if vi is required to be saved
        spl.selector.tag == :default && invlink!(vi, spl)
        c = save(c, spl, model, vi, samples)
    end
    return c
end

function step(model, spl::Sampler{<:StaticHamiltonian}, vi::VarInfo, is_first::Val{true})
    # Pre-conditioner
    # The condition below is to handle the imcompatibility of
    # new adapataion interface with adaptive sampler used in Gibbs
    # TODO: remove below when the interface is compatible with Gibbs by design
    pc = if :pc_type in keys(spl.info)
        spl.info[:pc_type](length(vi[spl]))
    else
        UnitPreConditioner()
    end
    spl.info[:wum] = NaiveCompAdapter(pc, FixedStepSize(spl.alg.epsilon))
    return vi, HMCStats(1.0, true, spl.alg.epsilon, 0)
end

function step(model, spl::Sampler{<:AdaptiveHamiltonian}, vi::VarInfo, is_first::Val{true})
    spl.selector.tag != :default && link!(vi, spl)
    epsilon = find_good_eps(model, spl, vi) # heuristically find good initial epsilon
    dim = length(vi[spl])
    spl.info[:wum] = ThreePhaseAdapter(spl, epsilon, dim)
    spl.selector.tag != :default && invlink!(vi, spl)
    return vi, true
end

function step(model, spl::Sampler{<:Hamiltonian}, vi::VarInfo, is_first::Val{false})
    # Get step size
    ϵ = getss(spl.info[:wum])
    Turing.DEBUG && @debug "current ϵ: $ϵ"

    Turing.DEBUG && @debug "X-> R..."
    if spl.selector.tag != :default
        link!(vi, spl)
        runmodel!(model, vi, spl)
    end

    grad_func = gen_grad_func(vi, spl, model)
    lj_func = gen_lj_func(vi, spl, model)
    rev_func = gen_rev_func(vi, spl)
    momentum_sampler = gen_momentum_sampler(vi, spl, spl.info[:wum].pc)
    H_func = gen_H_func(spl.info[:wum].pc)

    θ, lj = vi[spl], vi.logp

    θ_new, lj_new, stats = hmc_step(θ, lj, lj_func, grad_func, H_func, ϵ, spl.alg, momentum_sampler;
                                    rev_func=rev_func)
    α = stats.accept_ratio

    Turing.DEBUG && @debug "decide whether to accept..."
    if stats.is_accept
        vi[spl] = θ_new
        setlogp!(vi, lj_new)
    else
        vi[spl] = θ
        setlogp!(vi, lj)
    end

    if PROGRESS[] && spl.selector.tag == :default
        std_str = string(spl.info[:wum].pc)
        std_str = length(std_str) >= 32 ? std_str[1:30]*"..." : std_str
        haskey(spl.info, :progress) && ProgressMeter.update!(
            spl.info[:progress], spl.info[:progress].counter;
            showvalues = [(:ϵ, ϵ), (:α, α), (:pre_cond, std_str)],
        )
    end

    if spl.alg isa AdaptiveHamiltonian
        # vi2 = deepcopy(vi)
        # invlink!(vi2, spl)
        # adapt!(spl.info[:wum], α, vi2[spl])
        adapt!(spl.info[:wum], α, vi[spl])
    end

    Turing.DEBUG && @debug "R -> X..."
    spl.selector.tag != :default && invlink!(vi, spl)

    return vi, stats
end

function assume(spl::Sampler{<:Hamiltonian}, dist::Distribution, vn::VarName, vi::VarInfo)
    Turing.DEBUG && @debug "assuming..."
    updategid!(vi, vn, spl)
    r = vi[vn]
    # acclogp!(vi, logpdf_with_trans(dist, r, istrans(vi, vn)))
    # r
    Turing.DEBUG && @debug "dist = $dist"
    Turing.DEBUG && @debug "vn = $vn"
    Turing.DEBUG && @debug "r = $r" "typeof(r)=$(typeof(r))"
    r, logpdf_with_trans(dist, r, istrans(vi, vn))
end

function assume(spl::Sampler{<:Hamiltonian}, dists::Vector{<:Distribution}, vn::VarName, var::Any, vi::VarInfo)
    @assert length(dists) == 1 "[observe] Turing only support vectorizing i.i.d distribution"
    dist = dists[1]
    n = size(var)[end]

    vns = map(i -> copybyindex(vn, "[$i]"), 1:n)

    rs = vi[vns]  # NOTE: inside Turing the Julia conversion should be sticked to

    # acclogp!(vi, sum(logpdf_with_trans(dist, rs, istrans(vi, vns[1]))))

    if isa(dist, UnivariateDistribution) || isa(dist, MatrixDistribution)
        @assert size(var) == size(rs) "Turing.assume variable and random number dimension unmatched"
        var = rs
    elseif isa(dist, MultivariateDistribution)
        if isa(var, Vector)
            @assert length(var) == size(rs)[2] "Turing.assume variable and random number dimension unmatched"
            for i = 1:n
                var[i] = rs[:,i]
            end
        elseif isa(var, Matrix)
            @assert size(var) == size(rs) "Turing.assume variable and random number dimension unmatched"
            var = rs
        else
            error("[Turing] unsupported variable container")
        end
    end

    var, sum(logpdf_with_trans(dist, rs, istrans(vi, vns[1])))
end

observe(spl::Sampler{<:Hamiltonian}, d::Distribution, value::Any, vi::VarInfo) =
    observe(nothing, d, value, vi)

observe(spl::Sampler{<:Hamiltonian}, ds::Vector{<:Distribution}, value::Any, vi::VarInfo) =
    observe(nothing, ds, value, vi)