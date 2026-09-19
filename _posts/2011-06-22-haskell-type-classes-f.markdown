---
layout: post
title: "Emulating Haskell type classes in F#"
date: 2011-06-22 15:41:00
author: Aleksandr Shvedov
tags: fsharp haskell ploymorphism ad-hoc typeclasses fprog
---
Although I chose F# as my first functional language, I soon found myself learning about Haskell and OCaml as well. Both have extensive documentation, established programming practices, and large, welcoming communities compared with F#. After some exposure to ML languages, Haskell's syntax is not too difficult to pick up, and its language features soon become intriguing.

One feature I kept encountering was *type classes*, which have been part of Haskell for more than a decade. Type classes support *ad-hoc polymorphism*, in a way that resembles function overloading in object-oriented languages. They define operations over a particular set of types. For example, Haskell's `(+)` and `(==)` work with certain types, rather than with every type, and can be extended to user-defined types.

What does a type class look like? Here is `Eq`, which defines equality comparisons between two values:

```haskell
class Eq a where
  (==) :: a -> a -> Bool
  (/=) :: a -> a -> Bool

  x == y = not (x /= y)
  x /= y = not (x == y)
```

This declaration defines a type class named `Eq`. For each type `a` with an `Eq` instance, it provides two operations, `(==)` and `(/=)`, of type `a -> a -> Bool`. Each operation has a default implementation in terms of the other, so defining either one is enough to implement an instance.

Type class methods are functions with an interesting signature: `(==) :: Eq a => a -> a -> Bool`. The `Eq a =>` part is called a *context*. For a .NET programmer, it is helpful to compare this with a *generic type parameter constraint*: it requires an `Eq` instance for the type argument `a`.

Let's express the same idea as an ordinary abstract class in F#:

```fsharp
// an abstract class parameterized by 'a
[<AbstractClass>]
type Eq<'a>() =
  // no state, only abstract members
  abstract equals    : 'a -> 'a -> bool
  abstract notEquals : 'a -> 'a -> bool
  // default implementations of those members
  default __.equals x y = not (__.notEquals x y)
  default __.notEquals x y = not (__.equals x y)
```

The structure is very similar. Next, we need a *type class instance*, which supplies these operations for a concrete type:

```haskell
instance Eq Integer where
  (==) = eqInteger
```

We replace the type parameter `a` with the concrete type and implement one or both operations. Here, `eqInteger :: Integer -> Integer -> Bool` is a function specialized for integer equality. We can express the same idea in F#:

```fsharp
// a type class instance is represented by a subclass of Eq<'a>
let intEq =
  { new Eq<int>() with // a concrete choice of 'a
      override __.equals x y = (x = y) }
```

Haskell enforces instance uniqueness: we cannot define a second `Eq Integer` instance with a different implementation. Our F# encoding imposes no such restriction; we can create another object derived from `Eq<'a>` whenever we like.

Now we can write a function that uses the operations of `Eq`. This one removes every occurrence of a given element from a list:

```haskell
remove :: Eq a => a -> [a] -> [a]
remove x xs = filter (/= x) xs
```

The `Eq a` constraint has propagated into the type of `remove`. We can therefore use `remove` only with lists whose element type has an `Eq` instance. How can we implement the same function in F# without compiler support for type classes?

```fsharp
/// remove : Eq<'a> -> 'a -> 'a list -> 'a list
let remove (hidden: Eq<_>) x xs =
  List.filter (hidden.notEquals x) xs
```

We add an argument of type `Eq<'a>` containing the required instance. This technique is called *dictionary passing*: the Haskell compiler implicitly passes a dictionary containing the type class operations. In F#, we have to select the appropriate `Eq<'a>` object ourselves and pass it explicitly:

```fsharp
> remove intEq 1 [1; 2; 1; 1; 3]
val it : int list = [2; 3]
```

At this level, type classes amount to implicit arguments supplied by the compiler. If one function with an `Eq a` constraint calls another with the same constraint, it can simply pass the dictionary along. Calling a type class method is comparable to a virtual method call. Other functions with constraints receive additional hidden dictionary parameters, one for each required constraint.

A key property of type classes is that an instance is separate from the type it describes. We can define equality—an `Eq` instance—for a type from a third-party library without changing that library. There is no need to modify the original type to make it implement an equality interface. This separation enables approaches to the *[expression problem](https://en.wikipedia.org/wiki/Expression_problem)* and to [*open* data types and functions](http://lambda-the-ultimate.org/node/1453).

Contexts can appear not only in function signatures, but also in type class and instance declarations. In a class declaration, they introduce a form of inheritance:

```haskell
class (Eq a) => Ord a where
  compare              :: a -> a -> Ordering
  (<), (<=), (>), (>=) :: a -> a -> Bool
  max, min             :: a -> a -> a
```

A context can contain several constraints, so this also allows multiple inheritance between type classes. We can model these relationships with ordinary classes: use inheritance for a single superclass, or store the required superclass dictionaries inside another dictionary when there are several.

The more involved part is instance resolution: how the compiler finds the required type class instance. It plays a role similar to overload resolution in object-oriented languages. This becomes particularly interesting with extensions such as [multi-parameter type classes](https://wiki.haskell.org/Multi-parameter_type_class), which define operations for combinations of types, and [functional dependencies](https://wiki.haskell.org/Functional_dependencies) between those parameters.

Type classes have proved useful in Haskell, so why does F# not have them? F#'s object-oriented features—classes, virtual methods, and overloading—already let us express much of the same functionality, as the examples above demonstrate. Type classes would be an F#-specific feature, while much of their practical role is already covered by the .NET Framework's base class libraries.

There is still a large area of type class usage that we have not considered. It requires *type constructor polymorphism*, which I will discuss in the next post.