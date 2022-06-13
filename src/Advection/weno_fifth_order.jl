#####
##### Weighted Essentially Non-Oscillatory (WENO) fifth-order advection scheme
#####

const C3₀ = 3/10
const C3₁ = 3/5
const C3₂ = 1/10 

"""
    struct WENO5{FT, XT, YT, ZT, XS, YS, ZS, WF} <: AbstractUpwindBiasedAdvectionScheme{3}

Weighted Essentially Non-Oscillatory (WENO) fifth-order advection scheme.

$(TYPEDFIELDS)
"""
struct WENO5{FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP, CA} <: AbstractUpwindBiasedAdvectionScheme{3}
    
    "coefficient for ENO reconstruction on x-faces" 
    coeff_xᶠᵃᵃ::XT
    "coefficient for ENO reconstruction on x-centers"
    coeff_xᶜᵃᵃ::XT
    "coefficient for ENO reconstruction on y-faces"
    coeff_yᵃᶠᵃ::YT
    "coefficient for ENO reconstruction on y-centers"
    coeff_yᵃᶜᵃ::YT
    "coefficient for ENO reconstruction on z-faces"
    coeff_zᵃᵃᶠ::ZT
    "coefficient for ENO reconstruction on z-centers"
    coeff_zᵃᵃᶜ::ZT
    
    "coefficient for WENO smoothness indicators on x-faces"
    smooth_xᶠᵃᵃ::XS
    "coefficient for WENO smoothness indicators on x-centers"
    smooth_xᶜᵃᵃ::XS
    "coefficient for WENO smoothness indicators on y-faces"
    smooth_yᵃᶠᵃ::YS
    "coefficient for WENO smoothness indicators on y-centers"
    smooth_yᵃᶜᵃ::YS
    "coefficient for WENO smoothness indicators on z-faces"
    smooth_zᵃᵃᶠ::ZS
    "coefficient for WENO smoothness indicators on z-centers"
    smooth_zᵃᵃᶜ::ZS

    "bounds for maximum-principle-satisfying WENO scheme"
    bounds :: PP

    "advection scheme used near boundaries"
    child_advection :: CA

    function WENO5{FT, VI, WF}(coeff_xᶠᵃᵃ::XT, coeff_xᶜᵃᵃ::XT,
                               coeff_yᵃᶠᵃ::YT, coeff_yᵃᶜᵃ::YT, 
                               coeff_zᵃᵃᶠ::ZT, coeff_zᵃᵃᶜ::ZT,
                               smooth_xᶠᵃᵃ::XS, smooth_xᶜᵃᵃ::XS, 
                               smooth_yᵃᶠᵃ::YS, smooth_yᵃᶜᵃ::YS, 
                               smooth_zᵃᵃᶠ::ZS, smooth_zᵃᵃᶜ::ZS, 
                               bounds::PP, child_advection::CA) where {FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP, CA}

            return new{FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP, CA}(coeff_xᶠᵃᵃ, coeff_xᶜᵃᵃ, coeff_yᵃᶠᵃ, coeff_yᵃᶜᵃ, coeff_zᵃᵃᶠ, coeff_zᵃᵃᶜ,
                                                                   smooth_xᶠᵃᵃ, smooth_xᶜᵃᵃ, smooth_yᵃᶠᵃ, smooth_yᵃᶜᵃ, smooth_zᵃᵃᶠ, smooth_zᵃᵃᶜ, 
                                                                   bounds, child_advection)
    end
end

"""
    WENO5([FT = Float64;] grid = nothing, stretched_smoothness = false, zweno = false)

Construct a fifth-order weigthed essentially non-oscillatory advection scheme. The constructor allows
construction of WENO schemes on either uniform or stretched grids.

Keyword arguments
=================

  - `grid`: (defaults to `nothing`)
  - `stretched_smoothness`: When `true` it results in computing the coefficients for the smoothness
    indicators β₀, β₁ and β₂ so that they account for the stretched `grid`. (defaults to `false`)
  - `zweno`: When `true` implement a Z-WENO formulation for the WENO weights calculation. (defaults to
    `false`)

!!! warn "No support for WENO5 on curvilinear grids"
    Currently, WENO 5th-order advection schemes don't work for for curvilinear grids.
    Providing `WENO5(::AbstractCurvilinearGrid)` defaults to uniform setting, i.e.
    `WENO5(::AbstractCurvilinearGrid) = WENO5()`.

Not providing any keyword argument, `WENO5()` defaults to the uniform 5th-order coefficients ("uniform
setting) in all directions, using a JS-WENO formulation.

```jldoctest; filter = [r".*┌ Warning.*", r".*└ @ Oceananigans.*"]
julia> using Oceananigans

julia> WENO5()
┌ Warning: defaulting to uniform WENO scheme with Float64 precision, use WENO5(grid = grid) if this was not intended
└ @ Oceananigans.Advection .../src/Advection/weno_fifth_order.jl:90
WENO5 advection scheme with:
    ├── X regular
    ├── Y regular
    └── Z regular
```

`WENO5(grid = grid)` defaults to uniform interpolation coefficient for each of the grid directions that
is uniform (`typeof(Δc) <: Number`) while it precomputes the ENO coefficients for reconstruction for all
grid directions that are stretched. (After testing "on-the-fly" calculation of coefficients for stretched
directions ended up being way too expensive and, therefore, is not supported.)

```jldoctest
julia> using Oceananigans

julia> grid = RectilinearGrid(size = (3, 4, 5), x = (0, 1), y = (0, 1), z = [-10, -9, -7, -4, -1.5, 0]);

julia> WENO5(grid = grid)
WENO5 advection scheme with:
    ├── X regular
    ├── Y regular
    └── Z stretched
```

`WENO5(grid = grid, stretched_smoothness = true)` behaves similarly to `WENO5(grid = grid)` but,
additionally, it also computes the smoothness indicators coefficients, ``β₀``, ``β₁``, and ``β₂``,
taking into account the stretched dimensions.

`WENO5(zweno = true)` implements a Z-WENO formulation for the WENO weights calculation

Comments
========

All methods have the roughly the same execution speed except for `stretched_smoothness = true` that
requires more memory and is less computationally efficient, especially on GPUs. In addition, it has
not been found to be much impactful on the tested cases. As such, most of the times we urge users
to use `WENO5(grid = grid)`, as this increases accuracy on a stretched mesh  but does decreases
memory utilization (and also results in a slight speed-up).

(The above claims were made after some preliminary tests. Thus, we still users to perform some
benchmarks/checks before performing, e.g., a large simulation on a "weirdly" stretched grid.)

On the other hand, a Z-WENO formulation is *most of the times* beneficial (also in case of a uniform
mesh) with roughly the same performances (just a slight slowdown). The same can be said for the
stretched `WENO5(grid = grid)` formulation in case of stretched grids.

References
==========

Shu, Essentially Non-Oscillatory and Weighted Essentially Non-Oscillatory Schemes for Hyperbolic
    Conservation Laws, 1997, NASA/CR-97-206253, ICASE Report No. 97-65

Castro et al, High order weighted essentially non-oscillatory WENO-Z schemes for hyperbolic conservation
    laws, 2011, Journal of Computational Physics, 230(5), 1766-1792
"""

WENO5(grid, FT::DataType=Float64; kwargs...) = WENO5(FT; grid = grid, kwargs...)

function WENO5(FT::DataType = Float64; 
               grid = nothing, 
               stretched_smoothness = false, 
               zweno = true, 
               vector_invariant = nothing,
               bounds = nothing)
    
    if !(grid isa Nothing) 
        FT = eltype(grid)
    end

    weno_coefficients = compute_stretched_weno_coefficients(grid, stretched_smoothness, FT)

    VI = typeof(vector_invariant)

    child_advection = WENO3(FT; grid, stretched_smoothness, zweno, vector_invariant, bounds)

    return WENO5{FT, VI, zweno}(weno_coefficients..., bounds, child_advection)
end

# Flavours of WENO
const ZWENO         = WENO5{<:Any, <:Any, <:Any, <:Any, <:Any, <:Any, <:Any, <:Any, true}
const PositiveWENO5 = WENO5{<:Any, <:Any, <:Any, <:Any, <:Any, <:Any, <:Any, <:Any, <:Any, <:Tuple}

const WENOVectorInvariantVel{FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP}  = 
      WENO5{FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP} where {FT, XT, YT, ZT, XS, YS, ZS, VI<:VelocityStencil, WF, PP}
const WENOVectorInvariantVort{FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP} = 
      WENO5{FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP} where {FT, XT, YT, ZT, XS, YS, ZS, VI<:VorticityStencil, WF, PP}

const WENOVectorInvariant = WENO5{FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP} where {FT, XT, YT, ZT, XS, YS, ZS, VI<:SmoothnessStencil, WF, PP}

function Base.show(io::IO, a::WENO5{FT, RX, RY, RZ}) where {FT, RX, RY, RZ}
    print(io, "WENO5 advection scheme with: \n",
              "    ├── X $(RX == Nothing ? "regular" : "stretched") \n",
              "    ├── Y $(RY == Nothing ? "regular" : "stretched") \n",
              "    └── Z $(RZ == Nothing ? "regular" : "stretched")" )
end

Adapt.adapt_structure(to, scheme::WENO5{FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP}) where {FT, XT, YT, ZT, XS, YS, ZS, VI, WF, PP} =
     WENO5{FT, VI, WF}(Adapt.adapt(to, scheme.coeff_xᶠᵃᵃ), Adapt.adapt(to, scheme.coeff_xᶜᵃᵃ),
                       Adapt.adapt(to, scheme.coeff_yᵃᶠᵃ), Adapt.adapt(to, scheme.coeff_yᵃᶜᵃ),
                       Adapt.adapt(to, scheme.coeff_zᵃᵃᶠ), Adapt.adapt(to, scheme.coeff_zᵃᵃᶜ),
                       Adapt.adapt(to, scheme.smooth_xᶠᵃᵃ), Adapt.adapt(to, scheme.smooth_xᶜᵃᵃ),
                       Adapt.adapt(to, scheme.smooth_yᵃᶠᵃ), Adapt.adapt(to, scheme.smooth_yᵃᶜᵃ),
                       Adapt.adapt(to, scheme.smooth_zᵃᵃᶠ), Adapt.adapt(to, scheme.smooth_zᵃᵃᶜ),
                       Adapt.adapt(to, scheme.bounds),
                       Adapt.adapt(to, scheme.child_advection))

@inline boundary_buffer(::WENO5) = 3

@inline symmetric_interpolate_xᶠᵃᵃ(i, j, k, grid, ::WENO5, c) = symmetric_interpolate_xᶠᵃᵃ(i, j, k, grid, centered_fourth_order, c)
@inline symmetric_interpolate_yᵃᶠᵃ(i, j, k, grid, ::WENO5, c) = symmetric_interpolate_yᵃᶠᵃ(i, j, k, grid, centered_fourth_order, c)
@inline symmetric_interpolate_zᵃᵃᶠ(i, j, k, grid, ::WENO5, c) = symmetric_interpolate_zᵃᵃᶠ(i, j, k, grid, centered_fourth_order, c)

@inline symmetric_interpolate_xᶜᵃᵃ(i, j, k, grid, ::WENO5, u) = symmetric_interpolate_xᶜᵃᵃ(i, j, k, grid, centered_fourth_order, u)
@inline symmetric_interpolate_yᵃᶜᵃ(i, j, k, grid, ::WENO5, v) = symmetric_interpolate_yᵃᶜᵃ(i, j, k, grid, centered_fourth_order, v)
@inline symmetric_interpolate_zᵃᵃᶜ(i, j, k, grid, ::WENO5, w) = symmetric_interpolate_zᵃᵃᶜ(i, j, k, grid, centered_fourth_order, w)

# Unroll the functions to pass the coordinates in case of a stretched grid
@inline left_biased_interpolate_xᶠᵃᵃ(i, j, k, grid, scheme::WENO5, ψ, args...)  = weno_left_biased_interpolate_xᶠᵃᵃ(i, j, k, grid, scheme, ψ, i, Face, args...)
@inline left_biased_interpolate_yᵃᶠᵃ(i, j, k, grid, scheme::WENO5, ψ, args...)  = weno_left_biased_interpolate_yᵃᶠᵃ(i, j, k, grid, scheme, ψ, j, Face, args...)
@inline left_biased_interpolate_zᵃᵃᶠ(i, j, k, grid, scheme::WENO5, ψ, args...)  = weno_left_biased_interpolate_zᵃᵃᶠ(i, j, k, grid, scheme, ψ, k, Face, args...)

@inline right_biased_interpolate_xᶠᵃᵃ(i, j, k, grid, scheme::WENO5, ψ, args...) = weno_right_biased_interpolate_xᶠᵃᵃ(i, j, k, grid, scheme, ψ, i, Face, args...)
@inline right_biased_interpolate_yᵃᶠᵃ(i, j, k, grid, scheme::WENO5, ψ, args...) = weno_right_biased_interpolate_yᵃᶠᵃ(i, j, k, grid, scheme, ψ, j, Face, args...)
@inline right_biased_interpolate_zᵃᵃᶠ(i, j, k, grid, scheme::WENO5, ψ, args...) = weno_right_biased_interpolate_zᵃᵃᶠ(i, j, k, grid, scheme, ψ, k, Face, args...)

@inline left_biased_interpolate_xᶜᵃᵃ(i, j, k, grid, scheme::WENO5, ψ, args...)  = weno_left_biased_interpolate_xᶠᵃᵃ(i+1, j, k, grid, scheme, ψ, i, Center, args...)
@inline left_biased_interpolate_yᵃᶜᵃ(i, j, k, grid, scheme::WENO5, ψ, args...)  = weno_left_biased_interpolate_yᵃᶠᵃ(i, j+1, k, grid, scheme, ψ, j, Center, args...)
@inline left_biased_interpolate_zᵃᵃᶜ(i, j, k, grid, scheme::WENO5, ψ, args...)  = weno_left_biased_interpolate_zᵃᵃᶠ(i, j, k+1, grid, scheme, ψ, k, Center, args...)

@inline right_biased_interpolate_xᶜᵃᵃ(i, j, k, grid, scheme::WENO5, ψ, args...) = weno_right_biased_interpolate_xᶠᵃᵃ(i+1, j, k, grid, scheme, ψ, i, Center, args...)
@inline right_biased_interpolate_yᵃᶜᵃ(i, j, k, grid, scheme::WENO5, ψ, args...) = weno_right_biased_interpolate_yᵃᶠᵃ(i, j+1, k, grid, scheme, ψ, j, Center, args...)
@inline right_biased_interpolate_zᵃᵃᶜ(i, j, k, grid, scheme::WENO5, ψ, args...) = weno_right_biased_interpolate_zᵃᵃᶠ(i, j, k+1, grid, scheme, ψ, k, Center, args...)

# Stencil to calculate the stretched WENO weights and smoothness indicators
@inline left_stencil_x(i, j, k, ψ, args...) = @inbounds ( (ψ[i-3, j, k], ψ[i-2, j, k], ψ[i-1, j, k]), (ψ[i-2, j, k], ψ[i-1, j, k], ψ[i, j, k]), (ψ[i-1, j, k], ψ[i, j, k], ψ[i+1, j, k]) )
@inline left_stencil_y(i, j, k, ψ, args...) = @inbounds ( (ψ[i, j-3, k], ψ[i, j-2, k], ψ[i, j-1, k]), (ψ[i, j-2, k], ψ[i, j-1, k], ψ[i, j, k]), (ψ[i, j-1, k], ψ[i, j, k], ψ[i, j+1, k]) )
@inline left_stencil_z(i, j, k, ψ, args...) = @inbounds ( (ψ[i, j, k-3], ψ[i, j, k-2], ψ[i, j, k-1]), (ψ[i, j, k-2], ψ[i, j, k-1], ψ[i, j, k]), (ψ[i, j, k-1], ψ[i, j, k], ψ[i, j, k+1]) )

@inline right_stencil_x(i, j, k, ψ, args...) = @inbounds ( (ψ[i-2, j, k], ψ[i-1, j, k], ψ[i, j, k]), (ψ[i-1, j, k], ψ[i, j, k], ψ[i+1, j, k]), (ψ[i, j, k], ψ[i+1, j, k], ψ[i+2, j, k]) )
@inline right_stencil_y(i, j, k, ψ, args...) = @inbounds ( (ψ[i, j-2, k], ψ[i, j-1, k], ψ[i, j, k]), (ψ[i, j-1, k], ψ[i, j, k], ψ[i, j+1, k]), (ψ[i, j, k], ψ[i, j+1, k], ψ[i, j+2, k]) )
@inline right_stencil_z(i, j, k, ψ, args...) = @inbounds ( (ψ[i, j, k-2], ψ[i, j, k-1], ψ[i, j, k]), (ψ[i, j, k-1], ψ[i, j, k], ψ[i, j, k+1]), (ψ[i, j, k], ψ[i, j, k+1], ψ[i, j, k+2]) )

@inline left_stencil_x(i, j, k, ψ::Function, args...) = @inbounds ( (ψ(i-3, j, k, args...), ψ(i-2, j, k, args...), ψ(i-1, j, k, args...)), (ψ(i-2, j, k, args...), ψ(i-1, j, k, args...), ψ(i, j, k, args...)), (ψ(i-1, j, k, args...), ψ(i, j, k, args...), ψ(i+1, j, k, args...)) )
@inline left_stencil_y(i, j, k, ψ::Function, args...) = @inbounds ( (ψ(i, j-3, k, args...), ψ(i, j-2, k, args...), ψ(i, j-1, k, args...)), (ψ(i, j-2, k, args...), ψ(i, j-1, k, args...), ψ(i, j, k, args...)), (ψ(i, j-1, k, args...), ψ(i, j, k, args...), ψ(i, j+1, k, args...)) )
@inline left_stencil_z(i, j, k, ψ::Function, args...) = @inbounds ( (ψ(i, j, k-3, args...), ψ(i, j, k-2, args...), ψ(i, j, k-1, args...)), (ψ(i, j, k-2, args...), ψ(i, j, k-1, args...), ψ(i, j, k, args...)), (ψ(i, j, k-1, args...), ψ(i, j, k, args...), ψ(i, j, k+1, args...)) )

@inline right_stencil_x(i, j, k, ψ::Function, args...) = @inbounds ( (ψ(i-2, j, k, args...), ψ(i-1, j, k, args...), ψ(i, j, k, args...)), (ψ(i-1, j, k, args...), ψ(i, j, k, args...), ψ(i+1, j, k, args...)), (ψ(i, j, k, args...), ψ(i+1, j, k, args...), ψ(i+2, j, k, args...)) )
@inline right_stencil_y(i, j, k, ψ::Function, args...) = @inbounds ( (ψ(i, j-2, k, args...), ψ(i, j-1, k, args...), ψ(i, j, k, args...)), (ψ(i, j-1, k, args...), ψ(i, j, k, args...), ψ(i, j+1, k, args...)), (ψ(i, j, k, args...), ψ(i, j+1, k, args...), ψ(i, j+2, k, args...)) )
@inline right_stencil_z(i, j, k, ψ::Function, args...) = @inbounds ( (ψ(i, j, k-2, args...), ψ(i, j, k-1, args...), ψ(i, j, k, args...)), (ψ(i, j, k-1, args...), ψ(i, j, k, args...), ψ(i, j, k+1, args...)), (ψ(i, j, k, args...), ψ(i, j, k+1, args...), ψ(i, j, k+2, args...)) )

# Stencil for vector invariant calculation of smoothness indicators in the horizontal direction

# Parallel to the interpolation direction! (same as left/right stencil)
@inline tangential_left_stencil_u(i, j, k, ::Val{1}, u)  = @inbounds left_stencil_x(i, j, k, ℑyᵃᶠᵃ, u)
@inline tangential_left_stencil_u(i, j, k, ::Val{2}, u)  = @inbounds left_stencil_y(i, j, k, ℑyᵃᶠᵃ, u)
@inline tangential_left_stencil_v(i, j, k, ::Val{1}, v)  = @inbounds left_stencil_x(i, j, k, ℑxᶠᵃᵃ, v)
@inline tangential_left_stencil_v(i, j, k, ::Val{2}, v)  = @inbounds left_stencil_y(i, j, k, ℑxᶠᵃᵃ, v)

@inline tangential_right_stencil_u(i, j, k, ::Val{1}, u)  = @inbounds right_stencil_x(i, j, k, ℑyᵃᶠᵃ, u)
@inline tangential_right_stencil_u(i, j, k, ::Val{2}, u)  = @inbounds right_stencil_y(i, j, k, ℑyᵃᶠᵃ, u)
@inline tangential_right_stencil_v(i, j, k, ::Val{1}, v)  = @inbounds right_stencil_x(i, j, k, ℑxᶠᵃᵃ, v)
@inline tangential_right_stencil_v(i, j, k, ::Val{2}, v)  = @inbounds right_stencil_y(i, j, k, ℑxᶠᵃᵃ, v)

#####
##### Jiang & Shu (1996) WENO smoothness indicators. See also Equation 2.63 in Shu (1998)
#####

@inline left_biased_β₀(FT, ψ, ::Type{Nothing}, scheme, args...) = @inbounds FT(13/12) * (ψ[1] - 2ψ[2] + ψ[3])^two_32 + FT(1/4) * (3ψ[1] - 4ψ[2] +  ψ[3])^two_32
@inline left_biased_β₁(FT, ψ, ::Type{Nothing}, scheme, args...) = @inbounds FT(13/12) * (ψ[1] - 2ψ[2] + ψ[3])^two_32 + FT(1/4) * ( ψ[1]         -  ψ[3])^two_32
@inline left_biased_β₂(FT, ψ, ::Type{Nothing}, scheme, args...) = @inbounds FT(13/12) * (ψ[1] - 2ψ[2] + ψ[3])^two_32 + FT(1/4) * ( ψ[1] - 4ψ[2] + 3ψ[3])^two_32

@inline right_biased_β₀(FT, ψ, ::Type{Nothing}, scheme, args...) = @inbounds FT(13/12) * (ψ[1] - 2ψ[2] + ψ[3])^two_32 + FT(1/4) * ( ψ[1] - 4ψ[2] + 3ψ[3])^two_32
@inline right_biased_β₁(FT, ψ, ::Type{Nothing}, scheme, args...) = @inbounds FT(13/12) * (ψ[1] - 2ψ[2] + ψ[3])^two_32 + FT(1/4) * ( ψ[1]         -  ψ[3])^two_32
@inline right_biased_β₂(FT, ψ, ::Type{Nothing}, scheme, args...) = @inbounds FT(13/12) * (ψ[1] - 2ψ[2] + ψ[3])^two_32 + FT(1/4) * (3ψ[1] - 4ψ[2] +  ψ[3])^two_32

#####
##### Stretched smoothness indicators gathered from precomputed values.
##### The stretched values for β coefficients are calculated from 
##### Shu, NASA/CR-97-206253, ICASE Report No. 97-65
##### by hardcoding that p(x) is a 2nd order polynomial
#####

@inline function biased_left_β(ψ, scheme, r, dir, i, location) 
    @inbounds begin
        stencil = retrieve_left_smooth(scheme, r, dir, i, location)
        wᵢᵢ = stencil[1]   
        wᵢⱼ = stencil[2]
        result = 0
        @unroll for j = 1:3
            result += ψ[j] * ( wᵢᵢ[j] * ψ[j] + wᵢⱼ[j] * dagger(ψ)[j] )
        end
    end
    return result
end

@inline function biased_right_β(ψ, scheme, r, dir, i, location) 
    @inbounds begin
        stencil = retrieve_right_smooth(scheme, r, dir, i, location)
        wᵢᵢ = stencil[1]   
        wᵢⱼ = stencil[2]
        result = 0
        @unroll for j = 1:3
            result += ψ[j] * ( wᵢᵢ[j] * ψ[j] + wᵢⱼ[j] * dagger(ψ)[j] )
        end
    end
    return result
end

@inline left_biased_β₀(FT, ψ, T, scheme, args...) = biased_left_β(ψ, scheme, 0, args...) 
@inline left_biased_β₁(FT, ψ, T, scheme, args...) = biased_left_β(ψ, scheme, 1, args...) 
@inline left_biased_β₂(FT, ψ, T, scheme, args...) = biased_left_β(ψ, scheme, 2, args...) 

@inline right_biased_β₀(FT, ψ, T, scheme, args...) = biased_right_β(ψ, scheme, 2, args...) 
@inline right_biased_β₁(FT, ψ, T, scheme, args...) = biased_right_β(ψ, scheme, 1, args...) 
@inline right_biased_β₂(FT, ψ, T, scheme, args...) = biased_right_β(ψ, scheme, 0, args...) 

#####
##### VectorInvariant reconstruction (based on JS or Z) (z-direction Val{3} is different from x- and y-directions)
#####
##### Z-WENO-5 reconstruction (Castro et al: High order weighted essentially non-oscillatory WENO-Z schemes for hyperbolic conservation laws)
#####
##### JS-WENO-5 reconstruction
#####

for (side, coeffs) in zip([:left, :right], ([:C3₀, :C3₁, :C3₂], [:C3₂, :C3₁, :C3₀]))
    biased_weno5_weights = Symbol(side, :_biased_weno5_weights)
    biased_β₀ = Symbol(side, :_biased_β₀)
    biased_β₁ = Symbol(side, :_biased_β₁)
    biased_β₂ = Symbol(side, :_biased_β₂)
    
    tangential_stencil_u = Symbol(:tangential_, side, :_stencil_u)
    tangential_stencil_v = Symbol(:tangential_, side, :_stencil_v)

    biased_stencil_z = Symbol(side, :_stencil_z)
    
    @eval begin
        @inline function $biased_weno5_weights(FT, ψₜ, T, scheme, dir, idx, loc, args...)
            ψ₂, ψ₁, ψ₀ = ψₜ 
            β₀ = $biased_β₀(FT, ψ₀, T, scheme, dir, idx, loc)
            β₁ = $biased_β₁(FT, ψ₁, T, scheme, dir, idx, loc)
            β₂ = $biased_β₂(FT, ψ₂, T, scheme, dir, idx, loc)
            
            if scheme isa ZWENO
                τ₅ = abs(β₂ - β₀)
                α₀ = FT($(coeffs[1])) * (1 + (τ₅ / (β₀ + FT(ε)))^ƞ) 
                α₁ = FT($(coeffs[2])) * (1 + (τ₅ / (β₁ + FT(ε)))^ƞ) 
                α₂ = FT($(coeffs[3])) * (1 + (τ₅ / (β₂ + FT(ε)))^ƞ) 
            else
                α₀ = FT($(coeffs[1])) / (β₀ + FT(ε))^ƞ
                α₁ = FT($(coeffs[2])) / (β₁ + FT(ε))^ƞ
                α₂ = FT($(coeffs[3])) / (β₂ + FT(ε))^ƞ
            end
        
            Σα = α₀ + α₁ + α₂
            w₀ = α₀ / Σα
            w₁ = α₁ / Σα
            w₂ = α₂ / Σα
        
            return w₀, w₁, w₂
        end

        @inline function $biased_weno5_weights(FT, ijk, T, scheme, dir, idx, loc, ::Type{VelocityStencil}, u, v)
            i, j, k = ijk
            
            u₂, u₁, u₀ = $tangential_stencil_u(i, j, k, dir, u)
            v₂, v₁, v₀ = $tangential_stencil_v(i, j, k, dir, v)
        
            βu₀ = $biased_β₀(FT, u₀, T, scheme, Val(2), idx, loc)
            βu₁ = $biased_β₁(FT, u₁, T, scheme, Val(2), idx, loc)
            βu₂ = $biased_β₂(FT, u₂, T, scheme, Val(2), idx, loc)
        
            βv₀ = $biased_β₀(FT, v₀, T, scheme, Val(1), idx, loc)
            βv₁ = $biased_β₁(FT, v₁, T, scheme, Val(1), idx, loc)
            βv₂ = $biased_β₂(FT, v₂, T, scheme, Val(1), idx, loc)
                   
            β₀ = 0.5*(βu₀ + βv₀)  
            β₁ = 0.5*(βu₁ + βv₁)     
            β₂ = 0.5*(βu₂ + βv₂)  
        
            if scheme isa ZWENO
                τ₅ = abs(β₂ - β₀)
                α₀ = FT($(coeffs[1])) * (1 + (τ₅ / (β₀ + FT(ε)))^ƞ) 
                α₁ = FT($(coeffs[2])) * (1 + (τ₅ / (β₁ + FT(ε)))^ƞ) 
                α₂ = FT($(coeffs[3])) * (1 + (τ₅ / (β₂ + FT(ε)))^ƞ) 
            else    
                α₀ = FT($(coeffs[1])) / (β₀ + FT(ε))^ƞ
                α₁ = FT($(coeffs[2])) / (β₁ + FT(ε))^ƞ
                α₂ = FT($(coeffs[3])) / (β₂ + FT(ε))^ƞ
            end
                
            Σα = α₀ + α₁ + α₂
            w₀ = α₀ / Σα
            w₁ = α₁ / Σα
            w₂ = α₂ / Σα
        
            return w₀, w₁, w₂
        end

        @inline function $biased_weno5_weights(FT, ijk, T, scheme, ::Val{3}, idx, loc, ::Type{VelocityStencil}, u)
            i, j, k = ijk
            
            u₂, u₁, u₀ = $biased_stencil_z(i, j, k, u)
        
            β₀ = $biased_β₀(FT, u₀, T, scheme, Val(3), idx, loc)
            β₁ = $biased_β₁(FT, u₁, T, scheme, Val(3), idx, loc)
            β₂ = $biased_β₂(FT, u₂, T, scheme, Val(3), idx, loc)
        
            if scheme isa ZWENO
                τ₅ = abs(β₂ - β₀)
                α₀ = FT($(coeffs[1])) * (1 + (τ₅ / (β₀ + FT(ε)))^ƞ) 
                α₁ = FT($(coeffs[2])) * (1 + (τ₅ / (β₁ + FT(ε)))^ƞ) 
                α₂ = FT($(coeffs[3])) * (1 + (τ₅ / (β₂ + FT(ε)))^ƞ) 
            else    
                α₀ = FT($(coeffs[1])) / (β₀ + FT(ε))^ƞ
                α₁ = FT($(coeffs[2])) / (β₁ + FT(ε))^ƞ
                α₂ = FT($(coeffs[3])) / (β₂ + FT(ε))^ƞ
            end
                
            Σα = α₀ + α₁ + α₂
            w₀ = α₀ / Σα
            w₁ = α₁ / Σα
            w₂ = α₂ / Σα
        
            return w₀, w₁, w₂
        end
    end
end

#####
##### Biased interpolation functions
#####

pass_stencil(ψ, i, j, k, stencil) = ψ 
pass_stencil(ψ, i, j, k, ::Type{VelocityStencil}) = (i, j, k)

for (interp, dir, val, cT, cS) in zip([:xᶠᵃᵃ, :yᵃᶠᵃ, :zᵃᵃᶠ], [:x, :y, :z], [1, 2, 3], [:XT, :YT, :ZT], [:XS, :YS, :ZS]) 
    for side in (:left, :right)
        interpolate_func = Symbol(:weno_, side, :_biased_interpolate_, interp)
        stencil       = Symbol(side, :_stencil_, dir)
        weno5_weights = Symbol(side, :_biased_weno5_weights)
        biased_p₀ = Symbol(side, :_biased_p₀)
        biased_p₁ = Symbol(side, :_biased_p₁)
        biased_p₂ = Symbol(side, :_biased_p₂)

        @eval begin
            @inline function $interpolate_func(i, j, k, grid, 
                                               scheme::WENO5{FT, XT, YT, ZT, XS, YS, ZS}, 
                                               ψ, idx, loc, args...) where {FT, XT, YT, ZT, XS, YS, ZS}
                
                ψ₂, ψ₁, ψ₀ = ψₜ = $stencil(i, j, k, ψ, grid, args...)
                w₀, w₁, w₂ = $weno5_weights(FT, pass_stencil(ψₜ, i, j, k, Nothing), $cS, scheme, Val($val), idx, loc, Nothing, args...)
                return w₀ * $biased_p₀(scheme, ψ₀, $cT, Val($val), idx, loc) + 
                       w₁ * $biased_p₁(scheme, ψ₁, $cT, Val($val), idx, loc) + 
                       w₂ * $biased_p₂(scheme, ψ₂, $cT, Val($val), idx, loc)
            end

            @inline function $interpolate_func(i, j, k, grid, 
                                               scheme::WENOVectorInvariant{FT, XT, YT, ZT, XS, YS, ZS}, 
                                               ψ, idx, loc, VI, args...) where {FT, XT, YT, ZT, XS, YS, ZS}

                ψ₂, ψ₁, ψ₀ = ψₜ = $stencil(i, j, k, ψ, grid, args...)
                w₀, w₁, w₂ = $weno5_weights(FT, pass_stencil(ψₜ, i, j, k, VI), $cS, scheme, Val($val), idx, loc, VI, args...)
                return w₀ * $biased_p₀(scheme, ψ₀, $cT, Val($val), idx, loc) + 
                       w₁ * $biased_p₁(scheme, ψ₁, $cT, Val($val), idx, loc) + 
                       w₂ * $biased_p₂(scheme, ψ₂, $cT, Val($val), idx, loc)
            end
        end
    end
end

@inline coeff_left_p₀(scheme::WENO5{FT}, ::Type{Nothing}, args...) where FT = (  FT(1/3),    FT(5/6), - FT(1/6))
@inline coeff_left_p₁(scheme::WENO5{FT}, ::Type{Nothing}, args...) where FT = (- FT(1/6),    FT(5/6),   FT(1/3))
@inline coeff_left_p₂(scheme::WENO5{FT}, ::Type{Nothing}, args...) where FT = (  FT(1/3),  - FT(7/6),  FT(11/6))

@inline coeff_right_p₀(scheme::WENO5, ::Type{Nothing}, args...) = reverse(coeff_left_p₂(scheme, Nothing, args...)) 
@inline coeff_right_p₁(scheme::WENO5, ::Type{Nothing}, args...) = reverse(coeff_left_p₁(scheme, Nothing, args...)) 
@inline coeff_right_p₂(scheme::WENO5, ::Type{Nothing}, args...) = reverse(coeff_left_p₀(scheme, Nothing, args...)) 