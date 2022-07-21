abstract type Slate end

struct MLBSlate <: Slate
    positions::AbstractDict{<:AbstractString,<:Integer}
    players::AbstractVector{<:NamedTuple}
    games::AbstractVector{<:AbstractString}
    teams::AbstractVector{<:AbstractString}
    μ::AbstractVector{<:Real}
    Σ::AbstractMatrix{<:Real}
end

# Construct MLBSlate with DraftKings position numbers
function MLBSlate(players::AbstractVector{<:NamedTuple}, games::AbstractVector{<:AbstractString}, teams::AbstractVector{<:AbstractString}, μ::AbstractVector{<:Real}, Σ::AbstractMatrix{<:Real})
    positions = Dict(
        "P" => 2,
        "C" => 1,
        "1B" => 1,
        "2B" => 1,
        "3B" => 1,
        "SS" => 1,
        "OF" => 3
    )
    return MLBSlate(positions, players, games, teams, μ, Σ)
end