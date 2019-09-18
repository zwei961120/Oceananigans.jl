using .TurbulenceClosures: ∂z_aaf

abstract type AbstractBuoyancy{EOS} end
abstract type AbstractNonlinearEOS <: EquationOfState end

const Earth_gravitational_acceleration = 9.80665

#=
Supported buoyancy types:

- Nothing 
- SeawaterBuoyancy
=#

#####
##### Functions for buoyancy = nothing
#####

@inline buoyancy_perturbation(i, j, k, grid::AbstractGrid{T}, ::Nothing, C) where T = zero(T)
@inline N²(i, j, k, grid::AbstractGrid{T}, ::Nothing, C) where T = zero(T)

#####
##### Seawater buoyancy for buoyancy determined by temperature and salinity
#####

struct SeawaterBuoyancy{G, EOS} <: AbstractBuoyancy{EOS}
    gravitational_acceleration :: G
    equation_of_state :: EOS
end

function SeawaterBuoyancy(T=Float64; 
                          gravitational_acceleration = Earth_gravitational_acceleration, 
                          equation_of_state = LinearEquationOfState(T))
    return SeawaterBuoyancy{T, typeof(equation_of_state)}(gravitational_acceleration, equation_of_state)
end

@inline grav(b::SeawaterBuoyancy) = b.gravitational_acceleration

@inline N²(i, j, k, grid, b::SeawaterBuoyancy, C) = 
    grav(b) * (    thermal_expansion(i, j, k, grid, b.equation_of_state, C) * ∂z_aaf(i, j, k, grid, C.T)
                - haline_contraction(i, j, k, grid, b.equation_of_state, C) * ∂z_aaf(i, j, k, grid, C.S))

#####
##### Linear equation of state
#####

"""
    LinearEquationOfState{T} <: AbstractEquationOfState

Linear equation of state for seawater. 
"""
struct LinearEquationOfState{T} <: AbstractEquationOfState
    α :: T
    β :: T
end

"""
    LinearEquationOfState([T=Float64;] α=1.67e-4, β=7.80e-4)

Returns parameters for a linear equation of state for seawater with
thermal expansion coefficient `α` and haline contraction coefficient `β`.
The buoyancy perturbation associated with a linear equation of state is

    `b = g * α * T - g * β * S`

Default constants are taken from Table 1.2 (page 33) of Vallis, "Atmospheric and Oceanic Fluid 
Dynamics: Fundamentals and Large-Scale Circulation" (2ed, 2017).
"""
LinearEquationOfState(T=Float64; α=1.67e-4, β=7.80e-4) = 
    LinearEquationOfState{T}(α, β)

const LinearSeawaterBuoyancy = SeawaterBuoyancy{FT, <:LinearEquationOfState} where FT

@inline buoyancy_perturbation(i, j, k, grid, b::LinearSeawaterBuoyancy, C) = 
    return @inbounds grav(b) * (   b.equation_of_state.α * C.T[i, j, k]
                                 - b.equation_of_state.β * C.S[i, j, k] )

@inline  thermal_expansion(i, j, k, grid, eos::LinearEquationOfState, C) = eos.α
@inline haline_contraction(i, j, k, grid, eos::LinearEquationOfState, C) = eos.β

#####
##### Nonlinear equations of state
#####

@inline buoyancy_perturbation(i, j, k, grid, b::AbstractBuoyancy{<:AbstractNonlinearEOS}, C) = 
    - grav(b) * ρ′(i, j, k, grid, b.equation_of_state, C) / b.ρ₀

#####
##### Roquet et al 2015 idealized nonlinear equations of state
#####

# Reference: Table 3 in Roquet et el, "Defining a Simplified yet 'Realistic' Equation of State for Seawater", (JPO, 2015)
roquet_coeffs = Dict(
                  :linear => (R₀₁₀ = -1.775e-1, R₁₀₀ = 7.718e-1, R₀₂₀ = 0,         R₀₁₁ = 0,          R₂₀₀ = 0,         R₁₀₁ = 0,         R₁₁₀ = 0),
               :cabbeling => (R₀₁₀ = -0.844e-1, R₁₀₀ = 7.718e-1, R₀₂₀ = -4.561e-3, R₀₁₁ = 0,          R₂₀₀ = 0,         R₁₀₁ = 0,         R₁₁₀ = 0),
:cabbeling_thermobaricity => (R₀₁₀ = -0.651e-1, R₁₀₀ = 7.718e-1, R₀₂₀ = -5.027e-3, R₀₁₁ = -2.5681e-5, R₂₀₀ = 0,         R₁₀₁ = 0,         R₁₁₀ = 0),
                :freezing => (R₀₁₀ = -0.491e-1, R₁₀₀ = 7.718e-1, R₀₂₀ = -5.027e-3, R₀₁₁ = -2.5681e-5, R₂₀₀ = 0,         R₁₀₁ = 0,         R₁₁₀ = 0),
            :second_order => (R₀₁₀ =  0.182e-1, R₁₀₀ = 8.078e-1, R₀₂₀ = -4.937e-3, R₀₁₁ = -2.4677e-5, R₂₀₀ = -1.115e-4, R₁₀₁ = -8.241e-6, R₁₁₀ = -2.446e-3)
)

type_convert_roquet_coeffs(T, coeffs) = NamedTuple{propertynames(coeffs)}(Tuple(T(R) for R in coeffs))

"Return the geopotential depth at `i, j, k` at cell centers."
@inline D(i, j, k, grid) = @inbounds -grid.zC[k]

"""
    RoquetIdealizedNonlinearEOS{F, C, T} <: AbstractNonlinearEOS

Parameters associated with the idealized nonlinear equation of state proposed by
Roquet et al., "Defining a Simplified yet 'Realistic' Equation of State for Seawater", 
Journal of Physical Oceanography (2015).
"""
struct RoquetIdealizedNonlinearEOS{F, C, T} <: AbstractNonlinearEOS
        ρ₀ :: T
    coeffs :: C
end

"""
    RoquetIdealizedNonlinearEOS([T=Float64,] flavor, ρ₀=1025, coeffs=roquet_coeffs[flavor])

Returns parameters for an idealized nonlinear equation of state with reference density 
`ρ₀`. The `flavor` of the nonlinear equation of state is a symbol corresponding to one of 
the 5 equations of state in equations (12)--(15) of Roquet et al., "Defining a Simplified 
yet 'Realistic' Equation of State for Seawater", Journal of Physical Oceanography (2015). 
The equations of state define the density anomaly `ρ′`, and have the polynomial form

    `ρ′(T, S, D) = Σᵢⱼₐ Rᵢⱼₐ Tⁱ Sʲ Dᵃ`,

where `T` is conservative temperature, `S` is absolute salinity, and `D` is the 
geopotential depth, currently just `D = -z`. The `Rᵢⱼₐ` are constant coefficients.

Flavors of idealized nonlinear equations of state
=================================================

    - `:linear`: a linear equation of state, `ρ′ = R₁₀₀ * T + R₀₁₀ * S`

    - `:cabbeling`: includes quadratic temperature term, 
                    `ρ′ = R₁₀₀ * T + R₀₁₀ * S + R₀₂₀ * T^2`

    - `:cabbeling_thermobaricity`: includes 'thermobaricity' term, 
                                   `ρ′ = R₁₀₀ * T + R₀₁₀ * S + R₀₂₀ * T^2 + R₀₁₁ * T * D`

    - `:freezing`: same as `:cabbeling_thermobaricity` with modified constants to increase 
                   accuracy near freezing

    - `:second_order`: includes quadratic salinity, halibaricity, and thermohaline term,
                       `ρ′ = R₁₀₀ * T + R₀₁₀ * S + R₀₂₀ * T^2 + R₀₁₁ * T * D`
                             + R₂₀₀ * S^2 + R₁₀₁ * S * D + R₁₁₀ * S * T`
"""
function RoquetIdealizedNonlinearEOS(T, flavor=:cabbeling_thermobaricity; coeffs=roquet_coeffs[flavor], ρ₀=1025)
    typed_coeffs = type_convert_roquet_coeffs(coeffs)
    return RoquetIdealizedNonlinearEOS{flavor, typeof(typed_coeffs), T}(ρ₀, typed_coeffs)
end

RoquetIdealizedNonlinearEOS(flavor; kwargs...) = RoquetIdealizedNonlinearEOS(Float64, flavor; kwargs...)

@inline ρ′(i, j, k, eos::RoquetIdealizedNonlinearEOS, C) = 
    @inbounds (   eos.coeffs.R₁₀₀ * C.S[i, j, k]
                + eos.coeffs.R₀₁₀ * C.T[i, j, k]
                + eos.coeffs.R₀₂₀ * C.T[i, j, k]^2
                + eos.coeffs.R₀₁₁ * C.T[i, j, k] * D(i, j, k, grid)
                + eos.coeffs.R₂₀₀ * C.S[i, j, k]^2
                + eos.coeffs.R₁₀₁ * C.S[i, j, k] * D(i, j, k, grid)
                + eos.coeffs.R₁₁₀ * C.S[i, j, k] * C.T[i, j, k] )

@inline thermal_expansion(i, j, k, eos::RoquetIdealizedNonlinearEOS, C) = 
    @inbounds (   eos.coeffs.R₀₁₀
                + 2 * eos.coeffs.R₀₂₀ * C.T[i, j, k]
                + eos.coeffs.R₀₁₁ * D(i, j, k, grid)
                + eos.coeffs.R₁₁₀ * C.T[i, j, k] )

@inline haline_contraction(i, j, k, eos::RoquetIdealizedNonlinearEOS, C) = 
    @inbounds (   eos.coeffs.R₁₀₀
                + 2 * eos.coeffs.R₂₀₀ * C.S[i, j, k]
                + eos.coeffs.R₁₀₁ * D(i, j, k, grid)
                + eos.coeffs.R₁₁₀ * C.S[i, j, k] 

#=
# Optimiziations: do we need?
@inline ρ′(i, j, k, eos::RoquetIdealizedNonlinearEOS{:linear}, C) = 
    @inbounds (   eos.coeffs.R₁₀₀ * C.S[i, j, k]
                + eos.coeffs.R₀₁₀ * C.T[i, j, k] )

@inline ρ′(i, j, k, eos::RoquetIdealizedNonlinearEOS{:cabbeling}, C) = 
    @inbounds (   eos.coeffs.R₁₀₀ * C.S[i, j, k]
                + eos.coeffs.R₀₁₀ * C.T[i, j, k]
                + eos.coeffs.R₀₂₀ * C.T[i, j, k]^2 )

@inline ρ′(i, j, k, eos::RoquetIdealizedNonlinearEOS{<:Union{:cabbeling_thermobaricity, :freezing}}, C) =
    @inbounds (   eos.coeffs.R₁₀₀ * C.S[i, j, k]
                + eos.coeffs.R₀₁₀ * C.T[i, j, k]
                + eos.coeffs.R₀₂₀ * C.T[i, j, k]^2
                + eos.coeffs.R₀₁₁ * C.T[i, j, k] * D(i, j, k, grid) )
=#
