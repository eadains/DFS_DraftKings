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


struct PGASlate <: Slate
    positions::AbstractDict{<:AbstractString,<:Integer}
    players::AbstractVector{<:NamedTuple}
    μ::AbstractVector{<:Real}
    Σ::AbstractMatrix{<:Real}
end


function PGASlate(players::AbstractVector{<:NamedTuple}, μ::AbstractVector{<:Real}, Σ::AbstractMatrix{<:Real})
    positions = Dict(
        "G" => 6
    )
    return PGASlate(positions, players, μ, Σ)
end


abstract type TournyOptimData end


struct MLBTournyOptimData <: TournyOptimData
    slate::MLBSlate
    overlap::Integer
    payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}}
    order_stats_mu::AbstractDict{<:Integer,<:Real}
    order_stats_sigma::AbstractDict{<:Integer,<:Real}
    opp_cov::AbstractVector{<:Real}
end


function MLBTournyOptimData(slate::MLBSlate, payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}}, overlap::Integer, entries::Integer, samples::Integer)
    order_stats_mu, order_stats_sigma, opp_cov = get_order_stats(slate, payoffs, entries, samples)
    return MLBTournyOptimData(slate, overlap, payoffs, order_stats_mu, order_stats_sigma, opp_cov)
end


struct PGATournyOptimData <: TournyOptimData
    slate::PGASlate
    overlap::Integer
    payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}}
    order_stats_mu::AbstractDict{<:Integer,<:Real}
    order_stats_sigma::AbstractDict{<:Integer,<:Real}
    opp_cov::AbstractVector{<:Real}
end


function PGATournyOptimData(slate::PGASlate, payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}}, overlap::Integer, entries::Integer, samples::Integer)
    order_stats_mu, order_stats_sigma, opp_cov = get_order_stats(slate, payoffs, entries, samples)
    return PGATournyOptimData(slate, overlap, payoffs, order_stats_mu, order_stats_sigma, opp_cov)
end