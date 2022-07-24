using Tables
using Distributions
using CSV
include("./src/solve.jl")

function get_hist_mlb_slate(date::AbstractString)
    players = CSV.read("./data/mlb_realized_slates/$(date).csv", Tables.rowtable)
    μ = [player.Projection for player in players]
    Σ = makeposdef(Symmetric(CSV.read("./data/mlb_realized_slates/$(date)_cov.csv", header=false, types=Float64, Tables.matrix)))
    games = unique([player.Game for player in players])
    teams = unique([player.Team for player in players])
    return MLBSlate(players, games, teams, μ, Σ)
end

files = readdir("./data/mlb_realized_slates")
files = [file for file in files if ~occursin("cov", file)]

logprob = 0
for file in files
    println(file)
    slate = get_hist_mlb_slate(file[1:10])
    logprob += logpdf(MvNormal(slate.μ, slate.Σ), [x.Scored for x in slate.players])
    println("$(file) done.")
end

for file in files
    write_cov(file[1:10], hist)
    println(file)
end


function write_cov(date::AbstractString, hist::AbstractVector{<:NamedTuple})
    players = CSV.read("./data/mlb_realized_slates/$(date).csv", Tables.rowtable)
    corr = get_corr(hist, players)
    σ = get_sigma(hist, players)
    Σ = Diagonal(σ) * corr * Diagonal(σ)
    CSV.write("./data/mlb_realized_slates/$(date)_cov.csv", Tables.table(Σ), writeheader=false)
end


function get_sigma(hist, players)
    σ = Vector{Float64}(undef, length(players))
    for (i, player) in enumerate(players)
        records = get_hist_player_records(player, hist)
        if length(records) < 5
            position_records = get_hist_position_records(player.Position, player.Order, hist)
            σ[i] = std([x.Scored - x.Projection for x in position_records])
        else
            σ[i] = std([x.Scored - x.Projection for x in records])
        end
    end
    return σ
end


function get_hist_player_records(hist::AbstractVector{T}, player::NamedTuple) where {T<:NamedTuple}
    result = T[]
    for record in hist
        if record.Name == player.Name
            append!(result, Ref(record))
        end
    end
    return result
end


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
    return replace!(corr, NaN => 0.0)
end


"""
    players_corr(num::Integer, hist::AbstractVector{<:NamedTuple}, p1::NamedTuple, p2::NamedTuple)

Given two players, estimates their correlation.

If they are on the same team, finds every pair of historical players where:
    - the first has the same position and batting order as player 1
    - the second has the same position and batting order as player 2
    - both players are from the same team on the same date
Then it finds the 'num' number of pairs with the closest projections to the given players
and returns their correlation.

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
        #return correlation_test([x[1].Scored for x in pairs], [x[2].Scored for x in pairs])
        return cor([x[1].Scored for x in pairs], [x[2].Scored for x in pairs])
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