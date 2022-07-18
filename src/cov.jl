using CSV
using Tables
using Statistics


"""
    euclid_dist(x::Number, y::Number)

Computes the euclidean distance between two numbers.
Returns the absolute value of their difference
"""
function euclid_dist(x::Number, y::Number)
    return abs(x - y)
end


"""
    euclid_dist(x::Tuple{Number, Number}, y::Tuple{Number, Number})

Computes the Euclidean distance between two points in 2d space
"""
function euclid_dist(x::Tuple{Number,Number}, y::Tuple{Number,Number})
    return sqrt((x[1] - y[1])^2 + (x[2] - y[2])^2)
end


"""
    write_cov(num::Integer, date::AbstractString)

Reads players from CSV given by 'date' parameter and computes covariance matrix.
'num' parameter dictates how many samples are used for computing standard deviation and
correlation
"""
function write_cov(num::Integer, date::AbstractString)
    players = CSV.read("./data/slates/slate_$(date).csv", Tables.rowtable)
    hist = CSV.read("./data/linestar_data.csv", Tables.rowtable)
    corr = get_corr(num, hist, players)
    σ = get_sigma(num, hist, players)
    Σ = Diagonal(σ) * corr * Diagonal(σ)
    CSV.write("./data/slates/cov_$(date).csv", Tables.table(Σ), writeheader=false)
end


"""
    write_captain_cov(num::Integer, date::AbstractString)

Sames as 'write_cov' function except this is for DraftKings showdown format
where players can be selected as captains.
"""
function write_captain_cov(num::Integer, date::AbstractString)
    players = CSV.read("./data/slates/sd_slate_$(date).csv", Tables.rowtable)
    hist = CSV.read("./data/linestar_data.csv", Tables.rowtable)
    corr = get_captain_corr(num, hist, players)
    σ = get_captain_sigma(num, hist, players)
    Σ = Diagonal(σ) * corr * Diagonal(σ)
    CSV.write("./data/slates/sd_cov_$(date).csv", Tables.table(Σ), writeheader=false)
end


"""
    get_sigma(num::Integer, hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})

Computes standard deviation vector for given list of players.
'num' parameter controls the 'get_similar_std' function behavior
"""
function get_sigma(num::Integer, hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})
    σ = Vector{Float64}(undef, length(players))
    for (i, player) in enumerate(players)
        σ[i] = get_similar_std(num, hist, player)
    end
    return σ
end


"""
    get_captain_sigma(num::Integer, hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})

Gets standard deviation vector for DraftKings showdown format. Last half of vector is first half multiplied by 1.5.
This is to account for the fact that the captain versions of players get 1.5 times as many points, as so have
higher variances.
"""
function get_captain_sigma(num::Integer, hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})
    old_sigma = get_sigma(num, hist, players)
    new_sigma = cat(σ, 1.5 .* σ, dims=1)
    return new_sigma
end


"""
    get_similar_std(num::Integer, hist::AbstractVector{<:NamedTuple}, player::NamedTuple)

Using a k-nearest-neighbors-like approach, estimates the standard deviation of scored points
for a given player.

Given a player, this finds the 'num' number of players that have the closest historical projection
to the given player and also have the same position and batting order. Returns the standard
deviation of those players actually scored points.
"""
function get_similar_std(num::Integer, hist::AbstractVector{<:NamedTuple}, player::NamedTuple)
    # Find players with same position and batting order
    similar_players = [x for x in hist if (x.Position == player.Position) && (x.Order == player.Order)]
    # Form list of tuples where first element is historical points actually scored,
    # and second element is distance between the historical projection and the current players projection
    similar_proj = [(x.Scored, euclid_dist(player.Projection, x.Consensus)) for x in similar_players]
    # Sort by projection distance
    sort!(similar_proj, by=x -> x[2])
    # Return standard deviation of actually scored points from num number of players with the closest
    # projection to the current player
    # If number of similar players is less than num, just use however many there are
    if length(similar_players) < num
        return std([similar_proj[x][1] for x in 1:length(similar_players)])
    else
        return std([similar_proj[x][1] for x in 1:num])
    end
end


"""
    get_corr(num::Integer, hist::AbstractVector{<:NamedTuple}, slate::AbstractVector{<:NamedTuple})

Given a slate of players, computes full correlation matrix for them
"""
function get_corr(num::Integer, hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})
    corr = Matrix{Float64}(undef, length(players), length(players))

    # Iterate over upper triangular portion of matrix, including the diagonal
    Threads.@threads for i in 1:length(players)
        for j in i:length(players)
            if i == j
                # Diagonal is always 1
                corr[i, j] = 1
            else
                # Otherwise set symmetric correlation entries
                pair_corr = players_corr(num, hist, players[i], players[j])
                corr[i, j] = pair_corr
                corr[j, i] = pair_corr
            end
        end
    end
    return corr
end


"""
    get_captain_corr(num::Integer, hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})

Computes correlation matrix for DraftKings showdown format where 1 player is chosen as captain.
Ex: If originally there are 20 players, this matrix will have dimension 40x40 instead of 20x20
    It's 4 blocks of the 20x20 correlation matrices in each corner.
    So, entry (1,1) is the correlation of the original player with themselves and entry
    (1, 21) is the correlation of the Captain version of the player with their non-captain version, and so on
"""
function get_captain_corr(num::Integer, hist::AbstractVector{<:NamedTuple}, players::AbstractVector{<:NamedTuple})
    # Standard correlation matrix of players, say 20x20
    old_corr = get_corr(num, hist, players)
    # Now two blocks, 40x20
    column_stack = cat(old_corr, old_corr, dims=1)
    # Now 4 blocks, 40x40
    new_corr = cat(column_stack, column_stack, dims=2)
    return new_corr
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
function players_corr(num::Integer, hist::AbstractVector{<:NamedTuple}, p1::NamedTuple, p2::NamedTuple)
    if p1.Team == p2.Team
        pairs = player_pairs(hist, p1.Position, p1.Order, p2.Position, p2.Order, false)
    elseif p1.Opponent == p2.Team
        pairs = player_pairs(hist, p1.Position, p1.Order, p2.Position, p2.Order, true)
    else
        return 0.0
    end

    # List of tuples containing the players realized scores and their distance from the given player's projections
    results = [(x.Scored, y.Scored, euclid_dist((x.Consensus, y.Consensus), (p1.Projection, p2.Projection))) for (x, y) in pairs]
    # Sort by distance
    sort!(results, by=x -> x[3])

    if length(results) <= 2
        # There are 2 or fewer samples, return 0
        # We need more than 2 so that the degress of freedom of the correlation test is > 0
        return 0.0
    elseif length(results) < num
        # If there are less than num samples, use however many are availiable
        return correlation_test([results[x][1] for x in 1:length(results)], [results[x][2] for x in 1:length(results)])
    else
        return correlation_test([results[x][1] for x in 1:num], [results[x][2] for x in 1:num])
    end
end


"""
    player_pairs(hist::AbstractVector{<:NamedTuple}, p1_position::AbstractString, p1_order::Integer, p2_position::AbstractString, p2_order::Integer, opposing::Bool)

Finds pairs of players where the each player matches the position and order given, respectively.
Parameter opposing decides whether the pairs of players should be from opposing teams or the same team
"""
function player_pairs(hist::AbstractVector{<:NamedTuple}, p1_position::AbstractString, p1_order::Integer, p2_position::AbstractString, p2_order::Integer, opposing::Bool)
    p1_sim = [x for x in hist if (x.Position == p1_position) && (x.Order == p1_order)]
    p2_sim = [x for x in hist if (x.Position == p2_position) && (x.Order == p2_order)]
    if opposing
        pairs = [(p1_sim[i], p2_sim[j]) for i = 1:length(p1_sim), j = 1:length(p2_sim) if (p1_sim[i].Team == p2_sim[j].Opp_Team) && (p1_sim[i].Date == p2_sim[j].Date)]
    else
        pairs = [(p1_sim[i], p2_sim[j]) for i = 1:length(p1_sim), j = 1:length(p2_sim) if (p1_sim[i].Team == p2_sim[j].Team) && (p1_sim[i].Date == p2_sim[j].Date)]
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