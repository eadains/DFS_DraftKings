using CSV
using Tables
using Statistics
using HypothesisTests
using LinearAlgebra
using Memoize


"""
    makeposdef(mat::Symmetric{<:Real})

Transforms a Symmetric real-valued matrix into a positive definite matrix
Computes eigendecomposition of matrix, sets negative and zero eigenvalues
to small value (1e-10) and then reconstructs matrix
"""
function makeposdef(mat::Symmetric{<:Real})
    vals = eigvals(mat)
    vecs = eigvecs(mat)
    vals[vals.<=1e-10] .= 1e-10
    return Symmetric(vecs * Diagonal(vals) * vecs')
end


"""
    write_cov(num::Integer, date::AbstractString)

Reads players from CSV given by 'date' parameter and computes covariance matrix.
'num' parameter dictates how many samples are used for computing standard deviation and
correlation
"""
function get_mlb_cov(players::AbstractVector{<:NamedTuple}, hist::AbstractVector{<:NamedTuple})
    corr = get_corr(hist, players)
    σ = get_mlb_sigma(hist, players)
    Σ = Diagonal(σ) * corr * Diagonal(σ)
    # Return positive definite version of matrix
    return makeposdef(Symmetric(Σ))
end


"""
    get_pga_cov(players::AbstractVector{<:NamedTuple}, hist::AbstractVector{<:NamedTuple})

Get covariance matrix for PGA players
"""
function get_pga_cov(players::AbstractVector{<:NamedTuple}, hist::AbstractVector{<:NamedTuple})
    σ = get_pga_sigma(hist, players)
    # Golfers have no meaningful correlation between them, so use the identity matrix
    Σ = Diagonal(σ) * I * Diagonal(σ)
    return Σ
end


"""
    get_mlb_sigma(hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})

Find standard deviation vector for given players for MLB.
"""
function get_mlb_sigma(hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})
    σ = Vector{Float64}(undef, length(players))
    for (i, player) in enumerate(players)
        # Find historical score records for player
        records = get_hist_player_records(hist, player)
        # If there aren't many, use standard deviation of all records matching
        # the players order and position as a prior.
        if length(records) < 5
            position_records = get_hist_position_records(hist, player.Position, player.Order)
            σ[i] = std([x.Scored - x.Projection for x in position_records])
        else
            σ[i] = std([x.Scored - x.Projection for x in records])
        end
    end
    return σ
end


"""
    get_pga_sigma(hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})

Find standard deviation vector for given players for PGA.
"""
function get_pga_sigma(hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})
    σ = Vector{Float64}(undef, length(players))
    for (i, player) in enumerate(players)
        # Find historical score records for player
        records = get_hist_player_records(hist, player)
        # If there aren't many, use standard deviation of all historical
        # data as a prior
        if length(records) < 5
            σ[i] = std([x.Scored - x.Projection for x in hist])
        else
            σ[i] = std([x.Scored - x.Projection for x in records])
        end
    end
    return σ
end


"""
    get_hist_player_records(hist::AbstractVector{T}, player::NamedTuple) where {T<:NamedTuple}

Find all records in historical data with matching player name
"""
function get_hist_player_records(hist::AbstractVector{T}, player::NamedTuple) where {T<:NamedTuple}
    result = T[]
    for record in hist
        if record.Name == player.Name
            append!(result, Ref(record))
        end
    end
    return result
end


"""
    get_hist_position_records(hist::AbstractVector{T}, position, order) where {T<:NamedTuple}

Finds all records with given position and batting order
"""
function get_hist_position_records(hist::AbstractVector{T}, position, order) where {T<:NamedTuple}
    result = T[]
    for record in hist
        if record.Position == position && record.Order == order
            append!(result, Ref(record))
        end
    end
    return result
end



"""
    get_corr(num::Integer, hist::AbstractVector{<:NamedTuple}, slate::AbstractVector{<:NamedTuple})

Given a slate of players, computes full correlation matrix for them
"""
function get_corr(hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})
    corr = Matrix{Float64}(undef, length(players), length(players))

    # Iterate over upper triangular portion of matrix, including the diagonal
    Threads.@threads for i in 1:length(players)
        for j in i:length(players)
            if i == j
                # Diagonal is always 1
                corr[i, j] = 1
            else
                # Otherwise set symmetric correlation entries
                pair_corr = players_corr(hist, players[i], players[j])
                corr[i, j] = pair_corr
                corr[j, i] = pair_corr
            end
        end
    end
    return corr
end


"""
    players_corr(num::Integer, hist::AbstractVector{<:NamedTuple}, p1::NamedTuple, p2::NamedTuple)

Given two players, estimates their correlation.

If they are on the same team, finds every pair of historical players where:
    - the first has the same position and batting order as player 1
    - the second has the same position and batting order as player 2
    - both players are from the same team on the same date
Returns the correlation of those players

Similar process when the players are on opposing teams, except the pairs are from opposing teams on each date.
"""
function players_corr(hist::AbstractVector{<:NamedTuple}, p1::NamedTuple, p2::NamedTuple)
    if p1.Team == p2.Team
        pairs = player_pairs(hist, p1.Position, p1.Order, p2.Position, p2.Order, false)
    elseif p1.Opponent == p2.Team
        pairs = player_pairs(hist, p1.Position, p1.Order, p2.Position, p2.Order, true)
    else
        return 0.0
    end

    if length(pairs) <= 2
        # There are 2 or fewer samples, return 0
        # We need more than 2 so that the degress of freedom of the correlation test is > 0
        return 0.0
    else
        return correlation_test([x[1].Scored - x[1].Projection for x in pairs], [x[2].Scored - x[2].Projection for x in pairs])
    end
end


"""
    player_pairs(hist::AbstractVector{<:NamedTuple}, p1_position::AbstractString, p1_order::Integer, p2_position::AbstractString, p2_order::Integer, opposing::Bool)

Finds pairs of players where the each player matches the position and order given, respectively.
Parameter opposing decides whether the pairs of players should be from opposing teams or the same team.
This function is cached because there are only limited numbers of combinations of player positions and orders,
and this function is expensive
"""
@memoize function player_pairs(hist::AbstractVector{<:NamedTuple}, p1_position::AbstractString, p1_order::Integer, p2_position::AbstractString, p2_order::Integer, opposing::Bool)
    p1_sim = [x for x in hist if (x.Position == p1_position) && (x.Order == p1_order)]
    p2_sim = [x for x in hist if (x.Position == p2_position) && (x.Order == p2_order)]
    if opposing
        pairs = [(p1_sim[i], p2_sim[j]) for i = 1:length(p1_sim), j = 1:length(p2_sim) if (p1_sim[i].Team == p2_sim[j].Opponent) && (p1_sim[i].Date == p2_sim[j].Date) && (p1_sim[i].Name != p2_sim[j].Name)]
    else
        pairs = [(p1_sim[i], p2_sim[j]) for i = 1:length(p1_sim), j = 1:length(p2_sim) if (p1_sim[i].Team == p2_sim[j].Team) && (p1_sim[i].Date == p2_sim[j].Date) && (p1_sim[i].Name != p2_sim[j].Name)]
    end
    return pairs
end


"""
    correlation_test(scores_1::AbstractVector{<:Real}, scores_2::AbstractVector{<:Real})

Conducts a hypothesis test for the correlation of the two score vectors.
If we can reject the null hypothesis of 0 correlation with p-value <= 0.05 
it returns the point correlation estimates
If we cannot reject the null hypothesis, returns 0
"""
function correlation_test(scores_1::AbstractVector{<:Real}, scores_2::AbstractVector{<:Real})
    test = CorrelationTest(scores_1, scores_2)
    if pvalue(test) <= 0.05
        return test.r
    else
        return 0.0
    end
end