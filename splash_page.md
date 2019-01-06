---
title: Turing.jl
layout: splash
permalink: /splash/

header:
  # overlay_color: "#000"
  # overlay_filter: "0.0"
  btn_class: "btn--primary"
  overlay_image: /assets/turing-logo-new.svg
  actions:
    - label: "Get Started"
      btn_class: "btn--primary"
      url: "http://turing.ml/docs/get-started/"
    - label: "Documentation"
      url: "http://turing.ml/docs/"
    - label: "Tutorials"
      url: "http://turing.ml/tutorials/"
excerpt: "**Turing** is a universal probabilistic programming language with an intuitive modelling interface, composable probabilistic inference, and computational scalability."

intro:
  - excerpt: 'Turing provides Hamiltonian Monte Carlo and particle MCMC sampling algorithms for complex posterior distributions ideal for distributions involving discrete variables and stochastic control flows.'

current-features:
  - title: 'Current Features'

main-feature_row:
  - title: "Intuitive Syntax"
    excerpt: "Turing models are easy to read and write. Specify models quickly and easily."
  - title: "Universal"
    excerpt: "Turing supports models with stochastic control flow — models work the way you write them."
  - title: "Fully Hackable"
    excerpt: "Turing is written fully in Julia, and can be modified to suit your needs."

code-sample:
  - title: "A Quick Example"
    excerpt: "Turing's modelling syntax allows you to specify a model without unnessecary overhead. The code below specifies a Gaussian model."
    snippet: |
      # Define a Gausssian model.
      @model gdemo(x, y) = begin
        # Assume that variance follows an InverseGamma distribution.
        σ ~ InverseGamma(2,3)

        # Assume that μ follows a Normal distribution.
        μ ~ Normal(0,sqrt(σ))

        # Observe our two data points, x and y.
        x ~ Normal(m, sqrt(s))
        y ~ Normal(m, sqrt(s))
        return σ, μ
      end
    url: "http://turing.ml/docs/quick-start/"
    btn_label: "Quick Start"
    btn_class: "btn--inverse"

flux:
  - image_path: "http://turing.ml/tutorials/figures/3_BayesNN_12_1.svg"
    title: "Integrates With Other Deep Learning Packages"
    excerpt: "Turing supports Julia's [Flux](http://fluxml.ai/) package for automatic differentiation. Combine Turing and Flux to construct probabalistic variants of traditional machine learning models."
    url: "http://turing.ml/tutorials/3-bayesnn/"
    btn_label: "Bayesian Neural Network Tutorial"
    btn_class: "btn--inverse"


samplers:
  - image_path: /assets/sampler.svg
    title: "Large Sampling Library"
    excerpt: "Turing provides Hamiltonian Monte Carlo sampling for differentiable posterior distributions, Particle MCMC sampling for complex posterior distributions involving discrete variables and stochastic control flow, and Gibbs sampling which combines particle MCMC, HMC and many other MCMC algorithms."
    url: "http://turing.ml/docs/library/#samplers"
    btn_label: "Samplers"
    btn_class: "btn--inverse"

citing:
  - title: "Citing Turing"
  - overlay_color: "#000"
  - excerpt: '<sub>If you use **Turing** for your own research, please consider citing the following publication: Hong Ge, Kai Xu, and Zoubin Ghahramani: **Turing: Composable inference for probabilistic programming.** AISTATS 2018 [pdf](http://proceedings.mlr.press/v84/ge18b.html) [bibtex](https://dblp.org/rec/bib2/conf/aistats/GeXG18.bib)</sub>'
---

{% include feature*row id="main-feature*row" %} {% include feature*row*code id="code-sample" type="center-code" %} {% include feature*row id="samplers" type="left" %} {% include feature*row id="flux" type="right" %} {% include feature_row id="citing" type = "center-left" %}
