using Test
using POMDPs, POMDPModels
using POMDPPolicies, POMDPModelTools, POMDPTesting, BeliefUpdaters, POMDPSimulators
using QuickPOMDPs
using IncrementalPruning
const IP = IncrementalPruning
using JuMP
using GLPK
using POMDPs: solve # to resolve ambiguity with JuMP

@testset "Incremental Pruning Solver" begin
    @testset "Incremental Pruning Functions" begin
        # # dominate
        # return beleif state point where α dominates all other vectors in A
        α = [0.6, 0.6]
        A = Set([[1.0, -1.0], [0.0, 1.0]])
        x = IP.dominate(α, A, JuMP.with_optimizer(GLPK.Optimizer))
        @test x[1] ≈ 0.667 atol = 0.001

        # filter arrays
        # return the set of non-dominated vectors
        A = Set([[1.0, -1.0], [0.0, 1.0], [0.3, 0.2], [0.9, 0.9]])
        B = Set([[1.0, -1.0], [0.0, 1.0], [0.9, 0.9]])
        Af = IP.filtervec(A, JuMP.with_optimizer(GLPK.Optimizer))
        @test Af ⊆ B && B ⊆ Af # set equality

        # filter alpha vectors
        # return the set of non-dominated alpha vectors
        av1 = IP.AlphaVec([1.0, -1.0], 1)
        av2 = IP.AlphaVec([0.0, 1.0], 1)
        av3 = IP.AlphaVec([0.3, 0.2], 1)
        av4 = IP.AlphaVec([0.9, 0.9], 1)
        A = Set([av1,av2,av3,av4])
        B = Set([av1,av2,av4])
        Af = IP.filtervec(A, JuMP.with_optimizer(GLPK.Optimizer))
        @test Af ⊆ B && B ⊆ Af # set equality

        # cross sum
        # return all cross-combinations of sums
        A = Set([IP.AlphaVec([1.0, -1.0], 1), IP.AlphaVec([0.0, 1.0], 1)])
        B = Set([IP.AlphaVec([10.0, 10.0], 1), IP.AlphaVec([20.0, 20.0], 1), IP.AlphaVec([30.0, 30.0], 1)])
        AB = IP.xsum(A, B)
        @test length(AB) == 6 # total number of elements
        @test Set([IP.AlphaVec(pop!(A).alpha + pop!(B).alpha, 1)]) ⊆ AB # arbitrary element is correct

        # incprune
        # return the filtered, iterated cross-sum of the inputs
        A = Set([[1.0, -1.0], [0.0, 1.0]])
        B = Set([[1.0, -2.0], [0.0, 1.0], [0.9, 0.9]])
        C = Set([[1.0, -3.0], [0.0, 1.0], [0.1, 0.9]])
        D = Set([[1.0, -4.0], [0.0, 1.0], [0.1, 0.9], [0.3, 0.3]])
        SZ = [A, B, C, D]
        SZref = IP.filtervec(IP.xsum(IP.xsum(IP.xsum(A,B),C),D), JuMP.with_optimizer(GLPK.Optimizer))
        SZip = IP.incprune(SZ, JuMP.with_optimizer(GLPK.Optimizer))
        @test SZip ⊆ SZref && SZref ⊆ SZip # set equality

        # dpval
        # return a vector with the value of each state
        prob = BabyPOMDP()
        A = ordered_actions(prob)
        Z = ordered_observations(prob)
        a = A[1] # feed
        z = Z[2] # cry
        α = [-10.0, 0.0] # reward for: [hungry, full]
        valref = [-0.81, -5.0] # N-1 step value of S = [hungry, full]
        @test IP.dpval(α,a,z,prob) == valref

        # dpupdate
        # return value unclear
        prob = BabyPOMDP()
        av1 = IP.AlphaVec([1.0, -1.0], 1)
        av2 = IP.AlphaVec([0.0, 1.0], 1)
        V0 = Set([av1, av2])
        @test length(IP.dpupdate(V0, prob, StateActionReward(prob), JuMP.with_optimizer(GLPK.Optimizer))) == 2 # not sure why this is 2
    end

    @testset "Solver Functions" begin
        # PruneSolver
        # return simulated expected total discounted reward
        solver = PruneSolver()
        @test test_solver(solver, TigerPOMDP()) ≈ 17.71 atol = 0.01
        @test test_solver(solver, BabyPOMDP()) ≈ -17.96 atol = 0.01

        # action
        # return best action at a belief
        pomdp = TigerPOMDP()
        ns = length(states(pomdp))
        tpolicy = AlphaVectorPolicy(pomdp, [zeros(ns), ones(ns)], ordered_actions(pomdp))
        b = DiscreteBelief(pomdp, [0.8,0.2])
        @test action(tpolicy,b) == 1 # action "1" is optimal (action index = 2)

        # diff value
        # return maximum difference in value functions
        pomdp = TigerPOMDP()
        A = ordered_actions(pomdp)
        a1 = [4.0; 0.0]
        a2 = [0.0; 4.0]
        a3 = [-2.75; 2.75]
        a4 = [-2.8; 2.8]
        a5 = [2.8; 2.8]
        tX = [IP.AlphaVec(a1, A[1]); IP.AlphaVec(a2, A[2])]
        tY = [IP.AlphaVec(a3, A[3]), IP.AlphaVec(a4, A[3])]
        tZ = [IP.AlphaVec(a5, A[3])]
        @test IP.diffvalue(tY, tX, pomdp, StateActionReward(pomdp), JuMP.with_optimizer(GLPK.Optimizer)) ≈ 6.75 atol = 0.0001
        @test IP.diffvalue(tZ, tX, pomdp, StateActionReward(pomdp), JuMP.with_optimizer(GLPK.Optimizer)) ≈ 1.2 atol = 0.0001
    end
end

@testset "QuickPOMDP from POMDPs README" begin
    m = QuickPOMDP(
        states = [:left, :right],
        actions = [:left, :right, :listen],
        observations = [:left, :right],
        initialstate = Uniform([:left, :right]),
        discount = 0.95,
    
        transition = function (s, a)
            if a == :listen
                return Deterministic(s) # tiger stays behind the same door
            else # a door is opened
                return Uniform([:left, :right]) # reset
            end
        end,
    
        observation = function (s, a, sp)
            if a == :listen
                if sp == :left
                    return SparseCat([:left, :right], [0.85, 0.15]) # sparse categorical distribution
                else
                    return SparseCat([:right, :left], [0.85, 0.15])
                end
            else
                return Uniform([:left, :right])
            end
        end,
    
        reward = function (s, a, sp, o...) # QMDP needs R(s,a,sp), but simulations use R(s,a,sp,o)
            if a == :listen  
                return -1.0
            elseif s == a # the tiger was found
                return -100.0
            else # the tiger was escaped
                return 10.0
            end
        end
    )
    
    solver = PruneSolver()
    policy = solve(solver, m)
    
    rsum = 0.0
    for (s,b,a,o,r) in stepthrough(m, policy, "s,b,a,o,r", max_steps=10)
        println("s: $s, b: $([pdf(b,s) for s in states(m)]), a: $a, o: $o")
        rsum += r
    end
end
