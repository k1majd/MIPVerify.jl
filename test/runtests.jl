using MIPVerify: Conv2DParameters, PoolParameters, MaxPoolParameters, AveragePoolParameters, ConvolutionLayerParameters, MatrixMultiplicationParameters, SoftmaxParameters, FullyConnectedLayerParameters, increment!, getsliceindex, getpoolview, pool, relu, set_max_index, get_max_index, matmul, tight_upperbound, tight_lowerbound
using Base.Test
using Base.Test: @test_throws

using JuMP
using Gurobi

@testset "MIPVerify" begin
    @testset "LayerParameters" begin
        
        @testset "Conv2DParameters" begin
            @testset "With Bias" begin
                @testset "Matched Size" begin
                    out_channels = 5
                    filter = rand(3, 3, 2, out_channels)
                    bias = rand(out_channels)
                    p = Conv2DParameters(filter, bias)
                    @test p.filter == filter
                    @test p.bias == bias
                end
                @testset "Unmatched Size" begin
                    filter_out_channels = 4
                    bias_out_channels = 5
                    filter = rand(3, 3, 2, filter_out_channels)
                    bias = rand(bias_out_channels)
                    @test_throws AssertionError Conv2DParameters(filter, bias)
                end
            end
            @testset "No Bias" begin
                filter = rand(3, 3, 2, 5)
                p = Conv2DParameters(filter)
                @test p.filter == filter
            end
            @testset "JuMP Variables" begin
                m = Model()
                filter_size = (3, 3, 2, 5)
                filter = map(_ -> @variable(m), CartesianRange(filter_size))
                p = Conv2DParameters(filter)
                @test p.filter == filter
            end
        end
        
        @testset "PoolParameters" begin
            strides = (1, 2, 2, 1)
            p = PoolParameters(strides, x -> x)
            @test p.strides == strides
        end
        
        @testset "ConvolutionLayerParameters" begin
            filter_out_channels = 5
            filter = rand(3, 3, 1, filter_out_channels)
            bias = rand(filter_out_channels)
            strides = (1, 2, 2, 1)
            p = ConvolutionLayerParameters(filter, bias, strides)
            @test p.conv2dparams.filter == filter
            @test p.conv2dparams.bias == bias
            @test p.maxpoolparams.strides == strides
        end

        @testset "MatrixMultiplicationParameters" begin
            @testset "With Bias" begin
                @testset "Matched Size" begin
                    height = 10
                    matrix = rand(height, 2)
                    bias = rand(height)
                    p = MatrixMultiplicationParameters(matrix, bias)
                    @test p.matrix == matrix
                    @test p.bias == bias
                end
                @testset "Unmatched Size" begin
                    matrix_height = 10
                    bias_height = 5
                    matrix = rand(matrix_height, 2)
                    bias = rand(bias_height)
                    @test_throws AssertionError MatrixMultiplicationParameters(matrix, bias)
                end
            end
        end

        @testset "SoftmaxParameters" begin
            height = 10
            matrix = rand(height, 2)
            bias = rand(height)
            p = SoftmaxParameters(matrix, bias)
            @test p.mmparams.matrix == matrix
            @test p.mmparams.bias == bias
        end

        @testset "FullyConnectedLayerParameters" begin
            height = 10
            matrix = rand(height, 2)
            bias = rand(height)
            p = FullyConnectedLayerParameters(matrix, bias)
            @test p.mmparams.matrix == matrix
            @test p.mmparams.bias == bias
        end
    end 

    @testset "Layers" begin
        @testset "conv2d" begin
            srand(1)
            input_size = (1, 4, 4, 2)
            input = rand(0:5, input_size)
            filter_size = (3, 3, 2, 1)
            filter = rand(0:5, filter_size)
            bias_size = (1, )
            bias = rand(0:5, bias_size)
            true_output_raw = [
                49 74 90 56;
                67 118 140 83;
                66 121 134 80;
                56 109 119 62            
            ]
            true_output = reshape(transpose(true_output_raw), (1, 4, 4, 1))
            p = MIPVerify.Conv2DParameters(filter, bias)
            @testset "Numerical Input, Numerical Layer Parameters" begin
                evaluated_output = MIPVerify.conv2d(input, p)
                @test evaluated_output == true_output
            end
            @testset "Numerical Input, Variable Layer Parameters" begin
                m = Model(solver=GurobiSolver(OutputFlag=0))
                filter_v = map(_ -> @variable(m), CartesianRange(filter_size))
                bias_v = map(_ -> @variable(m), CartesianRange(bias_size))
                p_v = MIPVerify.Conv2DParameters(filter_v, bias_v)
                output_v = MIPVerify.conv2d(input, p_v)
                @constraint(m, output_v .== true_output)
                solve(m)

                p_solve = MIPVerify.Conv2DParameters(getvalue(filter_v), getvalue(bias_v))
                solve_output = MIPVerify.conv2d(input, p_solve)
                @test solve_output≈true_output
            end
            @testset "Variable Input, Numerical Layer Parameters" begin
                m = Model(solver=GurobiSolver(OutputFlag=0))
                input_v = map(_ -> @variable(m), CartesianRange(input_size))
                output_v = MIPVerify.conv2d(input_v, p)
                @constraint(m, output_v .== true_output)
                solve(m)

                solve_output = MIPVerify.conv2d(getvalue(input_v), p)
                @test solve_output≈true_output
            end
        end

        @testset "increment!" begin
            @testset "Real * Real" begin
                @test 7 == increment!(1, 2, 3)
            end
            @testset "JuMP.AffExpr * Real" begin
                m = Model()
                x = @variable(m, start=100)
                y = @variable(m, start=1)
                s = 5*x+3*y
                t = 3*x+2*y
                increment!(s, 2, t)
                @test getvalue(s)==1107
                increment!(s, t, -1)
                @test getvalue(s)==805
                increment!(s, x, 3)
                @test getvalue(s)==1105
                increment!(s, y, 2)
                @test getvalue(s)==1107
            end
        end
        
        @testset "Pooling operations" begin
            @testset "getsliceindex" begin
                @testset "inbounds" begin
                    @test getsliceindex(10, 2, 3)==[5, 6]
                    @test getsliceindex(10, 3, 4)==[10]
                end
                @testset "out of bounds" begin
                    @test getsliceindex(10, 5, 4)==[]
                end
            end
            
            input_size = (6, 6)
            input_array = reshape(1:*(input_size...), input_size)
            @testset "getpoolview" begin
                @testset "inbounds" begin
                    @test getpoolview(input_array, (2, 2), (3, 3)) == [29 35; 30 36]
                    @test getpoolview(input_array, (1, 1), (3, 3)) == cat(2, [15])
                end
                @testset "out of bounds" begin
                    @test length(getpoolview(input_array, (1, 1), (7, 7))) == 0
                end
            end

            @testset "maxpool" begin
                true_output = [
                    8 20 32;
                    10 22 34;
                    12 24 36
                ]
                @testset "Numerical Input" begin
                    @test pool(input_array, MaxPoolParameters((2, 2))) == true_output
                end
                @testset "Variable Input" begin
                    m = Model(solver=GurobiSolver(OutputFlag=0))
                    input_array_v = map(
                        i -> @variable(m, lowerbound=i-2, upperbound=i), 
                        input_array
                    )
                    pool_v = pool(input_array_v, MaxPoolParameters((2, 2)))
                    # elements of the input array are made to take their maximum value
                    @objective(m, Max, sum(input_array_v))
                    solve(m)

                    solve_output = getvalue.(pool_v)
                    @test solve_output≈true_output
                end
            end

            @testset "avgpool" begin
                @testset "Numerical Input" begin
                    true_output = [
                        4.5 16.5 28.5;
                        6.5 18.5 30.5;
                        8.5 20.5 32.5
                    ]
                    @test pool(input_array, AveragePoolParameters((2, 2))) == true_output
                end
            end

        end

        @testset "Maximum operations" begin
            @testset "Variable Input" begin
                m = Model(solver=GurobiSolver(OutputFlag=0))
                x1 = @variable(m, lowerbound=0, upperbound=3)
                x2 = @variable(m, lowerbound=4, upperbound=5)
                x3 = @variable(m, lowerbound=2, upperbound=7)
                x4 = @variable(m, lowerbound=-1, upperbound=1)
                x5 = @variable(m, lowerbound=-3, upperbound=1)
                xmax = MIPVerify.maximum([x1, x2, x3, x4, x5])
                # elements of the input array are made to take their maximum value
                @objective(m, Max, x1+x2+x3+x4+x5)
                solve(m)
                
                solve_output = getvalue(xmax)
                # an efficient implementation does not add binary variables for x1, x4 and x5
                num_binary_variables = count(x -> x == :Bin, m.colCat)

                @test solve_output==7
                @test num_binary_variables<= 2
            end
        end
        
        @testset "Relu operations" begin
            @testset "Numerical Input" begin
                @test relu(5)==5
                @test relu(0)==0
                @test relu(-1)==0           
            end
            
            @testset "Variable Input" begin
                @test 1==1
            end
        end

        @testset "Max index operations" begin
            @testset "set_max_index" begin
                @testset "no tolerance" begin
                    m = Model(solver=GurobiSolver(OutputFlag=0))
                    x = @variable(m, [i=1:3])
                    @constraint(m, x[2] == 5)
                    @constraint(m, x[3] == 1)
                    set_max_index(x, 1)
                    @objective(m, Min, x[1])
                    solve(m)
                    @test getvalue(x[1])==5
                end
                @testset "with tolerance" begin
                    tolerance = 3
                    m = Model(solver=GurobiSolver(OutputFlag=0))
                    x = @variable(m, [i=1:3])
                    @constraint(m, x[2] == 5)
                    @constraint(m, x[3] == 1)
                    set_max_index(x, 1, tolerance)
                    @objective(m, Min, x[1])
                    solve(m)
                    @test getvalue(x[1])==5+tolerance
                end
            end

            @testset "get_max_index" begin
                @test_throws MethodError get_max_index([])
                @test get_max_index([3]) == 1
                @test get_max_index([3, 1, 4]) == 3
                @test get_max_index([3, 1, 4, 1, 5, 9, 2]) == 6
            end
        end

        @testset "Bounds" begin
            m = Model(solver=GurobiSolver(OutputFlag=0))
            x = @variable(m, [i=1:2], lowerbound = -1, upperbound = 1)
            
            A1 = [1 -0.5; -0.5 1]
            b1 = zeros(2)
            p1 = MatrixMultiplicationParameters(A1, b1)
            # naive bounds on our intermediate activations are [-1, 1]
            # for both, but the extremal values are not simultaneously
            # achievable

            A2 = [1 1]
            b2 = zeros(1)
            p2 = MatrixMultiplicationParameters(A2, b2)
          
            output = matmul(matmul(x, p1), p2)[1]
            @test tight_upperbound(output) == 1
            @test tight_lowerbound(output) == -1
        end
    end
end

