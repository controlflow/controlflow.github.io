---
layout: post
title: "A brief introduction to kinds"
date: 2011-10-17 21:10:00
author: Aleksandr Shvedov
tags: haskell fprog types type theory kinds
---
Today, let us look at *kinds*: the types of types.

We will start with the basics. Programming languages have *values*, for example the following. All code examples in this post use Haskell:

```haskell
1           -- a number
[1, 2, 3]   -- a list
(1, "abc")  -- a tuple
```

In a typed language, these values have types:

```haskell
1           :: Int
[1, 2, 3]   :: [Int]
(1, "abc")  :: (Int, String)
```

We can write these types more explicitly, using the descriptive names `List` and `Pair` in place of Haskell's built-in list and tuple syntax:

```haskell
1           :: Int              -- in C-style languages:
[1, 2, 3]   :: List Int         -- List<Int>
(1, "abc")  :: Pair Int String  -- Pair<Int, String>
```

Some types are simple, while others are built by *applying parameterized types* to other types. Parameterized types are common in languages that support parametric polymorphism. They can have several type parameters, as with tuples or maps: `Map key value`. These polymorphic data types let us write generic code without knowing the concrete types supplied as arguments. For example, `map` works with *lists* whose elements can have any type.

Once a parameterized type has been *applied* to all of its type arguments, the result is an ordinary type, just like a simple type with no parameters. It can in turn be used as an argument to another parameterized type.

What, then, are `List`, `Pair`, and other parameterized types before they have been applied to arguments? They are *type constructors*, analogous to the data constructors introduced by `data` declarations. This is why I use the word “apply”: applying a type constructor to a type argument, as in `List Int`, resembles applying a data constructor to a value, as in `Just 1`. We can think of `List` as a *function over types*: it takes a type and returns a type.

A type constructor with several parameters can be viewed as a *curried function over types*. In Haskell, applying `Map` to one type argument, the key type, produces another type constructor. Applying that result to the value type gives an ordinary type. This is why `Map Int String` means `((Map Int) String)`. Just as with functions and values, we can use partial application at the type level. In many other languages, such as C#, all type arguments must be supplied at once. We can think of those constructors as functions taking a *tuple of type arguments*.

![We need to go deeper]({{ site.baseurl }}/images/go-deeper.jpg)

We now have different categories of types: ordinary types and functions over types. These categories act as *types of types*, which we call *kinds*. We write `*` for the kind of an ordinary type and use the familiar function arrow `→` for type constructors. Now we can assign kinds to types:

```haskell
Int           :: *
List Int      :: *
(Int, String) :: *
List          :: * → *
Map           :: * → * → *
```

The arrow `→` is right-associative, so the last kind can also be written as `* → (* → *)`. Kinds classify the entities in a type system, just as types classify values.

Most of the time, even in Haskell, programmers work with ordinary types of kind `*`. But Haskell has long supported type parameters with more interesting kinds. Type parameters have kinds too. For example:

```haskell
fmap :: Functor f => (a → b) → f a → f b
```

In this signature, the type parameter `f` is applied to `a` and `b`, so the compiler infers that `f` has kind `* → *`. A call to `fmap` therefore needs a type constructor with one parameter and a corresponding `Functor` instance. The function can transform a value of type `f a` into one of type `f b`, potentially changing the element type: for example, from `[Int]` to `[String]`, or from `Maybe Int` to `Maybe String`.

Types whose kinds differ from `*` are known as *higher-kinded types*. A related concept is *higher-kinded polymorphism*, also called *type constructor polymorphism*: parametric polymorphism in which type parameters can have kinds other than `*`, like `f` above. Besides Haskell, Scala is another well-known language that supports it.

Mainstream languages such as C# and Java also let us define and use type constructors whose kinds are not simply `*`. In .NET, these even have a runtime representation: `typeof(Dictionary<,>)`. However, they are not first-class entities in the type system: we cannot pass them as type arguments without first supplying their own arguments. There is therefore no higher-kinded polymorphism. Every type parameter has kind `*`; we cannot apply a type parameter as a constructor, as in `T<int>`.

There are more interesting combinations of kinds. Consider this data type declaration:

```haskell
data Foo m a = Foo (m a)
```

The parameter `m` has kind `* → *` because it is applied to `a`. The constructor `Foo` itself has kind `(* → *) → * → *`. Applying `Foo` to a constructor of kind `* → *`, then to an ordinary type, produces a type of kind `*`, such as `Foo List Int`. Notice how type application groups: this means `(Foo List) Int`.

Standard Haskell infers kinds from usage rather than allowing explicit kind annotations in the same way as type annotations for values. This sometimes leads to awkward workarounds, such as adding a dummy data constructor:

```haskell
data Set cxt a = Set [a]
               | Unused (cxt a → ())
```

Here, `Unused` exists solely to force `cxt` to have kind `* → *`, which is a rather clumsy solution. GHC provides an extension called *explicitly-kinded quantification*, enabled with `-XKindSignatures`, that allows explicit kind annotations:

```haskell
-- in data type declarations
data Set (cxt :: * → *) a = Set [a]

-- in type synonym declarations
type T (f :: * → *) = f Int

-- in type class declarations
class (Eq a) => C (f :: * → *) a where ...
```

A deeper treatment would take me beyond my knowledge of Haskell and type theory, so I will leave you with a few references:

* The [*constraint kinds* extension for GHC](http://blog.omega-prime.co.uk/?p=127) introduces the kind `Constraint`, allowing constraints on polymorphic types and functions to be parameterized.
* A kind system [may also distinguish unboxed types](http://hackage.haskell.org/trac/ghc/wiki/IntermediateTypes), traditionally assigned the kind `#`. Kinds can also have a relationship analogous to subtyping, called *subkinding*.
* [KindSystem](http://hackage.haskell.org/trac/ghc/wiki/KindSystem) and [PolymorphicKinds](http://hackage.haskell.org/trac/ghc/wiki/PolymorphicKinds) describe proposed GHC extensions that bring parametric polymorphism to the kind level and allow user-defined kinds. A familiar example is a list indexed by its length, expressed using the proposed syntax:

```haskell
data kind Nat = Zero | Succ Nat

data List :: * -> Nat -> * where
  Nil  :: List a Zero
  Cons :: a -> List a n -> List a (Succ n)
```

The second argument to `List` must have kind `Nat`. This kind includes `Zero` and the constructor `Succ`, which takes an argument of kind `Nat`. It resembles programming with values, but one level higher. Without a distinct `Nat` kind, it would be possible to construct a meaningless type such as `List Int Int`.