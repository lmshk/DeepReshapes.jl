module DeepReshapes

export describe, deep_length, deep_reshape, flatten, pack

# describe(x) recursively describes the dimensions of x
#   1. so that some deep reshapes can be reversed and
#   2. to determine the number of scalar values contained within (from
#      deep_length()).
#
# At the moment, the only recognized scalars are Numbers.
#
# In the untyped version (typed = false) this is a generalization of
# Base.size(): the specification of
#   - a scalar is an empty tuple,
#   - an Array of scalars is the Tuple of its dimensions,
#   - any other Array is the Array{Any} of specifications of its elements,
#   - a non-empty Tuple is the Tuple of specification of its elements,
#   - anything else is not defined.
#
# When typed = true, the specification of
#   - a scalar is its type,
#   - an Array of scalars is the Tuple of its element type concatenated with its
#     dimensions,
#   - and of all other objects is the same as in the untyped case.

describe{T <: Number}(x::T; typed::Bool = true) = typed ? T : ()

describe(x::(Any, Any...); typed::Bool = true) =
  tuple([describe(e, typed = typed) for e in x]...)

describe{T <: Number}(x::Array{T}; typed::Bool = true) =
  typed ? tuple(T, Base.size(x)...) : Base.size(x)

describe(x::Array; typed::Bool = true) =
  map!(e -> describe(e, typed = typed), similar(x, Any), x)
  # ^ We use map! here because we want to define the element type of the result.


# A deep_reshape(x, specification) iterates over all the scalars (recursively)
# contained within x, and from that stream writes into a new object whose
# structure is defined by specification.
#
# This happens in two independent processes which are executed in parallel:
#   - deep_produce() recursively walks the input and produces the scalars, and
#   - consume_stuctured() recursively builds the result from them according to
#     specification.
#
# By default, deep_produce() descends into Arrays and Tuples, but that behavior
# can be overridden by supplying the optional Deep argument. All encountered
# values that are not of Deep type are considered scalar by deep_produce() and
# therefore produced directly.
#
# The specification is of the same format that describe() returns.

DeepDefault = Union(Array, Tuple)

deep_reshape(x, specification; Deep = DeepDefault) =
  consume_stuctured(@task(deep_produce(x, Deep)), specification)

deep_reshape(x, specification...) = deep_reshape(x, specification)


# Descend into all x of Deep type.
deep_produce{T}(x::T, Deep::Type{T}) =
  for e in x; deep_produce(e, Deep) end

# Produce scalars directly.
deep_produce(x, ::Type) = produce(x)


# Consume a scalar or Array of scalars.
function consume_stuctured(
  producer::Task,
  Member::DataType,
  dimensions::Integer...
)
  if dimensions == ()
    convert(Member, consume(producer))
  else
    result = Array(Member, dimensions...)
    assign_entry(i...) = result[i...] = consume(producer)
    cartesianmap(assign_entry, dimensions)
  
    result
  end
end

# Consume a scalar or Array of scalars of unspecified type.
consume_stuctured(producer::Task, specification::(Integer...)) =
  consume_stuctured(producer, Any, specification...)

# Consume a scalar or Array of scalars of specific type.
consume_stuctured(producer::Task, specification::(DataType, Integer...)) =
  consume_stuctured(producer, specification...)
  
# Recursively consume any other Array.
function consume_stuctured(producer::Task, specification::Array)
  result = Array(Any, size(specification)...)
  assign_entry(i...) =
    result[i...] = consume_stuctured(producer, specification[i...])
  cartesianmap(assign_entry, size(specification))
  
  result
end

# Recursively consume a Tuple.
consume_stuctured(producer::Task, specification::Tuple) =
  tuple([consume_stuctured(producer, element) for element in specification]...)


# deep_length(x) returns the count of scalar values (recursively) contained
# within x. Only works where describe(x) also works.

deep_length(x) = specification_length(describe(x, typed = false))

specification_length(::()) = 1
specification_length(x::(Integer...)) = prod(x)
specification_length(x) = sum(specification_length, x)


# This is just a convenience wrapper to reshape any deep-reshapable into a flat
# Array, optionally with a fixed result element type.

flatten(MemberType::DataType, x...) =
  deep_reshape(x, MemberType, deep_length(x))

flatten(x...) = flatten(Any, x...)


# A convenience wrapper to ease converting between deep and flat representations
# of the same data.

function pack(MemberType::DataType, data...)
  s = describe(data, typed = false)
  l = specification_length(s)
  (deep_reshape(data, MemberType, l), s)
end

pack(x...) = pack(Any, x...)

end # module
