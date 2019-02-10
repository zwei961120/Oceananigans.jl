using Statistics: mean, std
using Printf

struct FieldSummary <: Diagnostic
    diagnostic_frequency::Int
    fields::Array{Field,1}
    field_names::Array{AbstractString,1}
end

function run_diagnostic(model::Model, fs::FieldSummary)
    for (field, field_name) in zip(fs.fields, fs.field_names)
        padded_name = lpad(field_name, 4)
        field_min = minimum(field.data)
        field_max = maximum(field.data)
        field_mean = mean(field.data)
        field_abs_mean = mean(abs.(field.data))
        field_std = std(field.data)
        @printf("%s: min=%.6g, max=%.6g, mean=%.6g, absmean=%.6g, std=%.6g\n",
                padded_name, field_min, field_max, field_mean, field_abs_mean, field_std)
    end
end

struct CheckForNaN <: Diagnostic end
struct VelocityDivergence <: Diagnostic end

mutable struct Nusselt_wT <: Diagnostic
    diagnostic_frequency::Int
    Nu::Array{AbstractFloat,1}
    wT_cumulative_running_avg::AbstractFloat
end

function run_diagnostic(model::Model, diag::Nusselt_wT)
    w, T = model.velocities.w.data, model.tracers.T.data
    V = model.grid.Lx * model.grid.Ly * model.grid.Lz
    wT_avg = sum(w .* T) / V

    n = length(diag.Nu)  # Number of "samples" so far.
    diag.wT_cumulative_running_avg = (wT_avg + n*model.clock.Δt*diag.wT_cumulative_running_avg) / ((n+1)*model.clock.Δt)

    Lz, κ, ΔT = model.grid.Lz, model.configuration.κh, 1
    Nu_wT = 1 + (Lz^2 / (κ*ΔT^2)) * diag.wT_cumulative_running_avg

    push!(diag.Nu, Nu_wT)
end