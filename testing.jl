include("./src/solve.jl")


model = Model(CPLEX.Optimizer)

p_prime = length(slate.players)
p = 2p_prime
# Players variable
@variable(model, x[1:p], binary = true)

# Total salary must be <= $50,000. Captain players cost 1.5x as much
@constraint(model, sum(slate.players[i].Salary * x[i] for i = 1:p_prime) + sum(slate.players[i-p_prime].Salary * 1.5 * x[i] for i = (p_prime+1):p) <= 50000)

for team in slate.teams
    # Must select at least 1 player from each team
    @constraint(model, sum(x[i] for i = 1:p_prime if slate.players[i].Team == team) + sum(x[i] for i = (p_prime+1):p if slate.players[i-p_prime].Team == team) >= 1)
end

# We must select one captain player
@constraint(model, sum(x[i] for i = (p_prime+1):p) == 1)
# We select 5 other players
@constraint(model, sum(x[i] for i = 1:p_prime) == 5)
# Cannot select same player for captain and non-captain position
@constraint(model, [i = 1:p_prime], x[i] + x[i+p_prime] <= 1)

# Maximize projected fantasy points, players selected for captain get 1.5x points
@objective(model, Max, sum(x[i] * slate.μ[i] for i = 1:p_prime) + sum(x[i] * 1.5 * slate.μ[i-p_prime] for i = (p_prime+1):p))

optimize!(model)
println(termination_status(model))

