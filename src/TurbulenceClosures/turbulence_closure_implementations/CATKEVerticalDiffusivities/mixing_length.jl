using Oceananigans.Operators

"""
    struct MixingLength{FT}

Contains mixing length parameters for CATKE vertical diffusivity.

The mixing length is the maximum of three mixing lengths:

```math
ℓᵩ = max(ℓᵟᵩ, ℓᴬᵩ, ℓ⋆ᵩ)
```            

where ``ℓᵟ`` is a grid-spacing-proportional length,
``ℓʰᵩ`` is a convective mixing length, and ``ℓ⋆ᵩ`` is
a mixing length in stably-stratified mixing.

Grid-spacing-proportional mixing length
=======================================

```math
ℓᵟᵩ = Cᵟϕ * Δz
```

Convective mixing length
========================

```math
ℓᴬᵩ = convecting ? Cᴬϕ * e^3/2 / Qᵇ : 0
```

Stably-stratified mixing length
===============================

```math
ℓ⋆ᵩ = σᵩ * min(d, Cᵇ * √e / N)
```

where ``σᵩ(Ri)`` is a stability function that depends on
the local Richardson number, ...

The Richardson number is

    ``Ri = ∂z B / ( (∂z U)² + (∂z V)² )`` ,

where ``B`` is buoyancy and ``∂z`` denotes a vertical derviative.
The Richardson-number dependent diffusivities are multiplied by the stability
function

    1. ``σ(Ri) = σ⁻ * (1 + rσ * step(Ri, Riᶜ, Riʷ))``

where ``σ₀``, ``Δσ``, ``Riᶜ``, and ``Riʷ`` are free parameters,
and ``step`` is a smooth step function defined by

    ``step(x, c, w) = (1 + \tanh((x - c) / w)) / 2``.

The 8 free parameters in `RiDependentDiffusivityScaling` have been _experimentally_ calibrated
against large eddy simulations of ocean surface boundary layer turbulence in idealized
scenarios involving monotonic boundary layer deepening into variable stratification
due to constant surface momentum fluxes and/or destabilizing surface buoyancy flux.
See https://github.com/CliMA/LESbrary.jl for more information about the large eddy simulations.
The calibration was performed using a combination of Markov Chain Monte Carlo (MCMC)-based simulated
annealing and noisy Ensemble Kalman Inversion methods.
"""
Base.@kwdef struct MixingLength{FT}
    Cᵇu   :: FT = 1.26
    Cᵇc   :: FT = 2.14
    Cᵇe   :: FT = 1.08
    Cˢu   :: FT = 0.82
    Cˢc   :: FT = 0.61
    Cˢe   :: FT = 1.47
    Cᵟu   :: FT = 0.5
    Cᵟc   :: FT = 0.5
    Cᵟe   :: FT = 0.5
    Cᴬu   :: FT = 0.0
    Cᴬc   :: FT = 0.0
    Cᴬe   :: FT = 0.0
    Cᴬˢu  :: FT = 0.0
    Cᴬˢc  :: FT = 0.0
    Cᴬˢe  :: FT = 0.0
    Cᴷu⁻  :: FT = 0.29
    Cᴷu⁺  :: FT = 0.75
    Cᴷc⁻  :: FT = 2.13
    Cᴷc⁺  :: FT = -0.27
    Cᴷe⁻  :: FT = 8.46
    Cᴷe⁺  :: FT = 1.49
    CᴷRiʷ :: FT = 3.14
    CᴷRiᶜ :: FT = Inf
end

#####
##### Mixing length
#####

@inline surface(i, j, k, grid)                = znode(Center(), Center(), Face(), i, j, grid.Nz+1, grid)
@inline bottom(i, j, k, grid)                 = znode(Center(), Center(), Face(), i, j, 1, grid)
@inline depthᶜᶜᶠ(i, j, k, grid)               = surface(i, j, k, grid) - znode(Center(), Center(), Face(), i, j, k, grid)
@inline height_above_bottomᶜᶜᶠ(i, j, k, grid) = znode(Center(), Center(), Face(), i, j, k, grid) - bottom(i, j, k, grid)

@inline wall_vertical_distanceᶜᶜᶠ(i, j, k, grid) = min(depthᶜᶜᶠ(i, j, k, grid), height_above_bottomᶜᶜᶠ(i, j, k, grid))

@inline function sqrt_∂z_b(i, j, k, grid, buoyancy, tracers)
    N² = ∂z_b(i, j, k, grid, buoyancy, tracers)
    N²⁺ = clip(N²)
    return sqrt(N²⁺)  
end

@inline ψ⁺(i, j, k, grid, ψ) = @inbounds clip(ψ[i, j, k])

@inline function buoyancy_mixing_lengthᶜᶜᶠ(i, j, k, grid, e, tracers, buoyancy)
    FT = eltype(grid)
    N⁺ = sqrt_∂z_b(i, j, k, grid, buoyancy, tracers)
    e⁺ = ℑzᵃᵃᶠ(i, j, k, grid, ψ⁺, e)
    return ifelse(N⁺ == 0, FT(Inf), sqrt(e⁺) / N⁺)
end

@inline function shear_mixing_lengthᶜᶜᶠ(i, j, k, grid, e, velocities, tracers, buoyancy)
    FT = eltype(grid)
    ∂z_u² = ℑxᶜᵃᵃ(i, j, k, grid, ϕ², ∂zᶠᶜᶠ, velocities.u)
    ∂z_v² = ℑyᵃᶜᵃ(i, j, k, grid, ϕ², ∂zᶜᶠᶠ, velocities.v)
    S = sqrt(∂z_u² + ∂z_v²)
    e⁺ = ℑzᵃᵃᶠ(i, j, k, grid, ψ⁺, e)
    return ifelse(S == 0, FT(Inf), sqrt(e⁺) / S)
end

@inline prodexp(x, α) = x * exp(- α * x)

@inline function smoothmin(a, b, c, α=1)
    numerator = prodexp(a, α) + 
                prodexp(b, α) + 
                prodexp(c, α)

    denominator = exp(- α * a) + exp(- α * b) + exp(- α * c)

    return numerator / denominator
end

#@inline smoothmin(α, x, y, z) = min(x, y, z)

@inline function stable_mixing_lengthᶜᶜᶠ(i, j, k, grid, Cᵇ::Number, Cˢ::Number, e, velocities, tracers, buoyancy)
    d = wall_vertical_distanceᶜᶜᶠ(i, j, k, grid)
    ℓᵇ = Cᵇ * buoyancy_mixing_lengthᶜᶜᶠ(i, j, k, grid, e, tracers, buoyancy)
    ℓˢ = Cˢ * shear_mixing_lengthᶜᶜᶠ(i, j, k, grid, e, velocities, tracers, buoyancy)
    #return smoothmin(d, ℓᵇ, ℓˢ)
    return min(d, ℓᵇ, ℓˢ)
end

@inline function convective_mixing_lengthᶜᶜᶠ(i, j, k, grid, Cᴬ::Number, Cᴬˢ::Number,
                                             velocities, tracers, buoyancy, clock, tracer_bcs)

    #=
    # Shear
    ∂z_u² = ℑxᶜᵃᵃ(i, j, k, grid, ϕ², ∂zᶠᶜᶠ, velocities.u)
    ∂z_v² = ℑyᵃᶜᵃ(i, j, k, grid, ϕ², ∂zᶜᶠᶠ, velocities.v)
    S = sqrt(∂z_u² + ∂z_v²)

    # Surface buoyancy flux
    Qᵇ = top_buoyancy_flux(i, j, grid, buoyancy, tracer_bcs, clock, merge(velocities, tracers))

    # Strictly positive TKE
    e⁺ = ℑzᵃᵃᶠ(i, j, k, grid, ψ⁺, tracers.e)
    
    # "Sheared convection number"
    α = S * Qᵇ / e⁺

    # Mixing length
    ℓᴬ = sqrt(e⁺^3) / Qᵇ
    ℓʰ = Cᴬ * ℓᴬ * (1 - Cᴬˢ * α)

    # Are we convecting?
    N² = ∂z_b(i, j, k, grid, buoyancy, tracers)
    d = depthᶜᶜᶠ(i, j, k, grid)
    convecting = ((N² < 0) | (d < ℓʰ)) & (Qᵇ > 0) & (e⁺ > 0)
    #convecting = (N² < 0) & (Qᵇ > 0)
    =#

    Qᵇ = top_buoyancy_flux(i, j, grid, buoyancy, tracer_bcs, clock, merge(velocities, tracers))
    N² = ∂z_b(i, j, k, grid, buoyancy, tracers)
    convecting = (N² < 0) & (Qᵇ > 0)
    ℓʰ = Cᴬ * Δzᶜᶜᶠ(i, j, k, grid)

    return ifelse(convecting, ℓʰ, zero(grid))
end

@inline ϕ²(i, j, k, grid, ϕ, args...) = ϕ(i, j, k, grid, args...)^2

@inline function Riᶜᶜᶜ(i, j, k, grid, velocities, tracers, buoyancy)
    ∂z_u² = ℑxzᶜᵃᶜ(i, j, k, grid, ϕ², ∂zᶠᶜᶠ, velocities.u)
    ∂z_v² = ℑyzᵃᶜᶜ(i, j, k, grid, ϕ², ∂zᶜᶠᶠ, velocities.v)
    N² = ℑzᵃᵃᶜ(i, j, k, grid, ∂z_b, buoyancy, tracers)
    return ifelse(N² <= 0, zero(grid), N² / (∂z_u² + ∂z_v²))
end

@inline function Riᶜᶜᶠ(i, j, k, grid, velocities, tracers, buoyancy)
    ∂z_u² = ℑxᶜᵃᵃ(i, j, k, grid, ϕ², ∂zᶠᶜᶠ, velocities.u)
    ∂z_v² = ℑyᵃᶜᵃ(i, j, k, grid, ϕ², ∂zᶜᶠᶠ, velocities.v)
    N² = ∂z_b(i, j, k, grid, buoyancy, tracers)
    return ifelse(N² <= 0, zero(grid), N² / (∂z_u² + ∂z_v²))
end

"""Piecewise linear function between 0 (when x < c) and 1 (when x - c > w)."""
@inline step(x, c, w) = max(zero(x), min(one(x), (x - c) / w)) # (1 + tanh(x / w - c)) / 2
@inline scale(Ri, σ⁻, σ⁺, c, w) = σ⁻ + (σ⁺ - σ⁻) * step(Ri, c, w)

@inline function momentum_stable_mixing_scale(i, j, k, grid, closure, velocities, tracers, buoyancy)
    Ri = Riᶜᶜᶠ(i, j, k, grid, velocities, tracers, buoyancy)
    return scale(Ri,
                 closure.mixing_length.Cᴷu⁻,
                 closure.mixing_length.Cᴷu⁺,
                 closure.mixing_length.CᴷRiᶜ,
                 closure.mixing_length.CᴷRiʷ)
end

@inline function tracer_stable_mixing_scale(i, j, k, grid, closure, velocities, tracers, buoyancy)
    Ri = Riᶜᶜᶠ(i, j, k, grid, velocities, tracers, buoyancy)
    return scale(Ri,
                 closure.mixing_length.Cᴷc⁻,
                 closure.mixing_length.Cᴷc⁺,
                 closure.mixing_length.CᴷRiᶜ,
                 closure.mixing_length.CᴷRiʷ)
end

@inline function TKE_stable_mixing_scale(i, j, k, grid, closure, velocities, tracers, buoyancy)
    Ri = Riᶜᶜᶠ(i, j, k, grid, velocities, tracers, buoyancy)
    return scale(Ri,
                 closure.mixing_length.Cᴷe⁻,
                 closure.mixing_length.Cᴷe⁺,
                 closure.mixing_length.CᴷRiᶜ,
                 closure.mixing_length.CᴷRiʷ)
end

@inline function momentum_mixing_lengthᶜᶜᶠ(i, j, k, grid, closure, velocities, tracers, buoyancy, clock, tracer_bcs)
    Cᴬ = closure.mixing_length.Cᴬu
    Cᴬˢ = closure.mixing_length.Cᴬˢu
    ℓʰ = convective_mixing_lengthᶜᶜᶠ(i, j, k, grid, Cᴬ, Cᴬˢ, velocities, tracers, buoyancy, clock, tracer_bcs)

    Cᵟ = closure.mixing_length.Cᵟu
    ℓᵟ = Cᵟ * Δzᶜᶜᶠ(i, j, k, grid)

    σu = momentum_stable_mixing_scale(i, j, k, grid, closure, velocities, tracers, buoyancy)
    Cᵇ = closure.mixing_length.Cᵇu
    Cˢ = closure.mixing_length.Cˢu
    ℓ★ = σu * stable_mixing_lengthᶜᶜᶠ(i, j, k, grid, Cᵇ, Cˢ, tracers.e, velocities, tracers, buoyancy)

    return ℓᵟ + ℓ★ + ℓʰ
end

@inline function tracer_mixing_lengthᶜᶜᶠ(i, j, k, grid, closure, velocities, tracers, buoyancy, clock, tracer_bcs)
    Cᴬ = closure.mixing_length.Cᴬc
    Cᴬˢ = closure.mixing_length.Cᴬˢc
    ℓʰ = convective_mixing_lengthᶜᶜᶠ(i, j, k, grid, Cᴬ, Cᴬˢ, velocities, tracers, buoyancy, clock, tracer_bcs)

    Cᵟ = closure.mixing_length.Cᵟc
    ℓᵟ = Cᵟ * Δzᶜᶜᶠ(i, j, k, grid)

    σc = tracer_stable_mixing_scale(i, j, k, grid, closure, velocities, tracers, buoyancy)
    Cᵇ = closure.mixing_length.Cᵇc
    Cˢ = closure.mixing_length.Cˢc
    ℓ★ = σc * stable_mixing_lengthᶜᶜᶠ(i, j, k, grid, Cᵇ, Cˢ, tracers.e, velocities, tracers, buoyancy)

    return ℓᵟ + ℓ★ + ℓʰ
end

@inline function TKE_mixing_lengthᶜᶜᶠ(i, j, k, grid, closure, velocities, tracers, buoyancy, clock, tracer_bcs)
    Cᴬ = closure.mixing_length.Cᴬe
    Cᴬˢ = closure.mixing_length.Cᴬˢe
    ℓʰ = convective_mixing_lengthᶜᶜᶠ(i, j, k, grid, Cᴬ, Cᴬˢ, velocities, tracers, buoyancy, clock, tracer_bcs)

    Cᵟ = closure.mixing_length.Cᵟe
    ℓᵟ = Cᵟ * Δzᶜᶜᶠ(i, j, k, grid)

    σe = TKE_stable_mixing_scale(i, j, k, grid, closure, velocities, tracers, buoyancy)
    Cᵇ = closure.mixing_length.Cᵇe
    Cˢ = closure.mixing_length.Cˢe
    ℓ★ = σe * stable_mixing_lengthᶜᶜᶠ(i, j, k, grid, Cᵇ, Cˢ, tracers.e, velocities, tracers, buoyancy)

    return ℓᵟ + ℓ★ + ℓʰ
end

Base.show(io::IO, ML::MixingLength) =
    print(io, "MixingLength:", "\n",
              "     Cᵇu  = $(ML.Cᵇu)",   "\n",
              "     Cᵇc  = $(ML.Cᵇc)",   "\n",
              "     Cᵇe  = $(ML.Cᵇe)",   "\n",
              "     Cˢu  = $(ML.Cˢu)",   "\n",
              "     Cˢc  = $(ML.Cˢc)",   "\n",
              "     Cˢe  = $(ML.Cˢe)",   "\n",
              "     Cᵟu  = $(ML.Cᵟu)",   "\n",
              "     Cᵟc  = $(ML.Cᵟc)",   "\n",
              "     Cᵟe  = $(ML.Cᵟe)",   "\n",
              "     Cᴬu  = $(ML.Cᴬu)",   "\n",
              "     Cᴬc  = $(ML.Cᴬc)",   "\n",
              "     Cᴬe  = $(ML.Cᴬe)",   "\n",
              "     Cᴷu⁻ = $(ML.Cᴷu⁻)",  "\n",
              "     Cᴷc⁻ = $(ML.Cᴷc⁻)",  "\n",
              "     Cᴷe⁻ = $(ML.Cᴷe⁻)",  "\n",
              "     Cᴷu⁺ = $(ML.Cᴷu⁺)",  "\n",
              "     Cᴷc⁺ = $(ML.Cᴷc⁺)",  "\n",
              "     Cᴷe⁺ = $(ML.Cᴷe⁺)",  "\n",
              "    CᴷRiʷ = $(ML.CᴷRiʷ)", "\n",
              "    CᴷRiᶜ = $(ML.CᴷRiᶜ)")
