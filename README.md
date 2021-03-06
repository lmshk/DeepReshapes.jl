# DeepReshapes

Extends
[reshape](http://julia.readthedocs.org/en/latest/stdlib/base/#Base.reshape)
to arbitrarily nested structures of `Tuple`s and `Array`s, both in source and
target. Also provides a deep `flatten` function that transforms these structures
into a flat `Vector`.

As I am pretty new to Julia, before I consider registering this package, I would
like a code review to know whether I am actually doing this "right". Please just
have a look, and if you think this is useful and ready, open an issue or
something like that.

Note that this only works on Julia 0.4 right now.

## What?

Provides a `deep_reshape` function that can transform the structure of data:

```
A = [1 2; 3 4; 5 6]
b = [1, 2, 3, 4]
deep_reshape((A, b), (2, 5))
# => [1 5 4 1 3;
#     3 2 6 2 4]

deep_reshape([1:25], ((3, 3), (4, 4)))
# => ([ 1  4  7;
#       2  5  8;
#       3  6  9],
#     [10 14 18 22;
#      11 15 19 23;
#      12 16 20 24;
#      13 17 21 25])

α, β, c = deep_reshape([1.23, 2.34, 3, 4, 5], (Float64, Float64, (Int, 3)))
# => (1.23,2.34,[3,4,5])
```

This works on all (potentially nested) structures of `Tuple`s and `Array`s, as
long as the actual scalar values contained within are `Number`s (for now).

## Why?

Say you want to optimize a non-linear function. Many optimization frameworks
([NLopt](https://github.com/JuliaOpt/NLopt.jl),
[Optim](https://github.com/JuliaOpt/Optim.jl)) require you to supply cost and
gradient functions and expect them to operate on plain `Vector{Float64}`s for
that purpose. However, some algorithms are expressed more naturally in terms of
more structured data.

Consider for example the popular
[backpropagation algorithm]
(http://ufldl.stanford.edu/wiki/index.php/Backpropagation_Algorithm)
for training neural networks. The outline of the gradient calculation might look
like this:

```
function cost_and_gradient!(
  W::Vector{Matrix{Float64}},  # weight matrices for each neuron layer
  b::Vector{Vector{Float64}},  # bias vectors for each neuron layer
  ∇W::Vector{Matrix{Float64}}, # vector to receive resulting weight gradients
  ∇b::Vector{Vector{Float64}}  # vector to receive resulting bias gradients
)
  # ...do feedforward and backpropagation, obtain some intermediate results
  # ...calculate gradients and fill the result vectors ∇W and ∇b
  # ...calculate and return the cost
end
```

For optimization, we cannot use this function directly, because the optimization
package expects it to work on plain number vectors:

```
using NLopt

W, b = initialize_parameters()
# ...we need to flatten W, b to number vector θ

optimization = Opt(:LD_LBFGS, length(θ))
min_objective!(optimization, cost_and_gradient!) # <- we need to define this
result = optimize(optimization, θ)
```

Flattening the initial parameters is easy with `flatten`:

```
using DeepReshapes

θ = flatten(Float64, W, b)
```

As for `cost_and_gradient!`, we can simply wrap the original calculation with
`deep_reshape`s:

```
function cost_and_gradient!(θ::Vector{Float64}, ∇θ::Vector{Float64})
  W, b = deep_reshape(θ, s) # <- s is a specification of the original structure
                            # which can be obtained by calling describe on the
                            # initial parameters before flattening them.

  # ...do the original calculation
  ∇θ[:] = flatten(Float64, ∇W, ∇b)
  # ... calculate and return the cost
end
```

## How?

A deep reshape consists of two independent processes: a *producer* that
recursively walks the input to produce scalar values, and a *consumer* that
consumes these values and puts them into a new object according to a structure
specification:

```
result = deep_reshape(input, specification)
```

### Source

The input can be any object, but by default, the producer only descends into
Arrays and Tuples and considers anything else to be a scalar:

```
deep_reshape([1:4], (2, 2)) # => Any[1 3; 2 4]
deep_reshape(1:4, (2, 2))   # => Any[1:4 (); () ()]
```

What objects to descend into can be overridden through the optional `Deep`
argument:

```
deep_reshape(1:4, (2, 2), Deep = Range)
```

Any input of type `Deep` will be considered iterable and all contained values
will be produced. Any other input will be considered scalar and produced
directly, without further recursion.

### Target

The produced scalars will then be assigned into the objects under construction 
according to the specification, which is of the following format:

- An empty tuple `()` describes `Any` value.
- A `Type` describes a value of that type.
- A tuple of `(Integer...)` dimensions describes an `Any[]` with these
  dimensions.
- A tuple `(Type, Integer...)` of a type and dimensions describes an Array
  with that element type and these dimensions.
- Any other `Tuple` recursively describes a tuple, where each contained value
  describes an entry of the result.
- An `Array` recursively describes an array in the same way.

For simple inputs (recursively) consisting only of `Tuple`s, `Array`s and
scalars, `describe()` returns the corresponding specification:

```
s = describe(([1:10], [1 2; 3 4])) # => ((Int, 10), (Int, 2, 2))
```

These can be used directly as `deep_reshape` specifications:

```
nested = deep_reshape([1:14], s)
# => ([1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
#     [11 13;
#      12 14])
```

### flatten and pack

There is also a convenience function `flatten` that can recursively flattens the
input to a `Vector`, optionally with a fixed target type that the scalars are to
be converted to:

```
flatten(nested)
# => Any[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]

flatten(Int, nested)
# => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
```

The very similar `pack` function returns both the flattened `Vector` and the
original structure as defined by `describe`. This can be used to later reverse
the flattening:

```
flattened, s = pack(Int, ([1:10], [1 2; 3 4]))
# => ([1,2,3,4,5,6,7,8,9,10,1,3,2,4],(((Int,10),(Int,2,2)),))

deep_reshape(flattened, s)
# => ([1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
#     [11 13;
#      12 14])
```
