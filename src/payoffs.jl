include("types.jl")


"""
    compute_rankings(scores::AbstractVector{<:Real})

Computes scoring ranks given a set of scores.
Returns a dictionary where each key is a rank and each value is a vector
of scores having that rank. This is so ties can be handled.

Example: If there are 3 scores tied for 2nd place, then the return dictionary
         will have a key "2" with a length 3 vector of that tied score.
         It will then not have keys 3 and 4, because those ranks are
         subsumed by the tied players. This is important for calculating payoffs

IMPORTANT: THIS FUNCTION ASSUMES SCORES IS SORTED FROM HIGHEST TO LOWEST
           RUN sort!(scores, rev=true) FIRST
"""
function compute_rankings(scores::AbstractVector{<:Real})
    output = Dict{Int,Vector{Float64}}()
    i = 1
    tie_count = 1
    prev_score = 0.0
    for score in scores
        if score == prev_score
            # If there is a tie, continue adding scores to the place
            # they are tied for and keep incrementing the rank
            # so the next non-tied entry has the right rank
            append!(output[i-tie_count], score)
            i += 1
            tie_count += 1
        else
            # Otherwise, reset the tie count, and add the next score
            # to the next rank and increment
            tie_count = 1
            output[i] = [score]
            i += 1
            prev_score = score
        end
    end
    return output
end

"""
    get_rank_payoff(desired_rank::Integer, payoffs::AbstractVector{<:Tuple{<:Integer, <:Real}})

Using a vector of tuples representing ranks and their payoffs, this computes the payoff
for any arbitrary rank.

Example: Payoff vector may be [(1, 50), (5, 0)]
         This means that ranks 1, 2, 3, and 4 have payoffs of 50 and ranks 5 and onward have payoff 0
         This function returns that information for any rank

IMPORTANT: THIS FUNCTION ASSUMES PAYOFFS ARE SORTED BY RANKS FROM LEAST TO GREATEST
           RUN sort!(payoffs, by=x -> x[1]) FIRST
"""
function get_rank_payoff(desired_rank::Integer, payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}})
    previous_payoff = 0.0
    for (rank, payoff) in payoffs
        if rank < desired_rank
            # If current rank is smaller than desired, update payoff
            previous_payoff = payoff
            continue
        elseif rank == desired_rank
            # If rank matches exactly, then return that payoff
            return payoff
        else
            # Otherwise, return the tracked payoff
            return previous_payoff
        end
    end
    # If nothing applies, our desired rank is higher than the last
    # listed payoff rank, so its 0
    return 0.0
end


"""
    compute_payoff(new_score::Real, payoffs::AbstractVector{<:Tuple{<:Integer, <:Real}}, all_scores::AbstractVector{<:Real})

Given a set of opponent scores and payoffs, computes the payoff for a new supplied score.

IMPORTANT: ASSUMES PAYOFFS AND SCORES ARE SORTED APPROPRIATELY AS DEFINED IN THE PREVIOUS TWO FUNCTIONS
"""
function compute_payoff(new_score::Real, payoffs::AbstractVector{<:Tuple{<:Integer,<:Real}}, all_scores::AbstractVector{<:Real})
    rankings = compute_rankings(all_scores)
    for i in sort(collect(keys(rankings)))
        if new_score == rankings[i][1]
            # If new score matches rankings score exactly, there is a tie and payoffs are summed and divded equally
            # For instance, if there are two people tied for first, add the prizes for 1st and 2nd and split it
            return sum(get_rank_payoff(n, payoffs) for n = i:i+length(rankings[i])) / (length(rankings[i]) + 1)
        elseif new_score > rankings[i][1]
            # If new score is higher than the ranking score, that means the new score takes that rank
            return get_rank_payoff(i, payoffs)
        end
    end
    # If new_score ranks past the bottom of the rankings list, then payoff is always 0
    return 0.0
end


"""
    get_expected_payoff(new_lineup::AbstractVector{<:Integer}, past_lineups::AbstractVector{<:AbstractVector{<:Integer}}, data::TournyOptimData)

Computes expected payoff of given lineup using past lineups and the necessary optimization data
"""
function get_expected_payoff(new_lineup::AbstractVector{<:Integer}, past_lineups::AbstractVector{<:AbstractVector{<:Integer}}, data::TournyOptimData)
    payoffs = Vector{Float64}(undef, length(data.score_draws))
    Threads.@threads for i = 1:length(data.score_draws)
        new_lineup_score = data.score_draws[i] ⋅ new_lineup
        past_lineups_scores = Float64[data.score_draws[i] ⋅ x for x in past_lineups]
        all_scores = [data.opp_scores[i]; past_lineups_scores]
        sort!(all_scores, rev=true)
        payoffs[i] = compute_payoff(new_lineup_score, data.payoffs, all_scores)
    end
    return mean(payoffs)
end