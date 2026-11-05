## Small result types for operations whose callers must distinguish failure causes.
## `ok` is the source of truth. `error` is meaningful only when `ok` is false.
## The zero enum value is a `none` sentinel so a forgotten error cannot look like
## a specific rejection reason.

type
  Status*[E] = object
    ok*: bool
    error*: E

  Result*[T, E] = object
    ok*: bool
    value*: T
    error*: E

proc okStatus*[E](_: typedesc[E]): Status[E] =
  Status[E](ok: true)

proc errStatus*[E](err: E): Status[E] =
  Status[E](ok: false, error: err)

proc okResult*[T, E](value: T; _: typedesc[E]): Result[T, E] =
  Result[T, E](ok: true, value: value)

proc errResult*[T, E](_: typedesc[T]; err: E): Result[T, E] =
  Result[T, E](ok: false, error: err)
