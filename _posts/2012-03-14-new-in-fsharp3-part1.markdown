---
layout: post
title: "What's new in F# 3.0: auto-properties"
date: 2012-03-14 15:56:08
author: Aleksandr Shvedov
tags: fsharp autoprops fprog
---
Today I want to look at the new features in F# 3.0, a general-purpose language that supports multiple paradigms while putting functional programming first. At the time of writing, this version is available only as part of [Visual Studio “11” Beta](http://www.microsoft.com/visualstudio/11/en-us), which is a little disappointing. There are not many new features, but some are significant. This post focuses on auto-properties.

F# has a fairly intricate syntax for defining ordinary classes, which I keep forgetting. Once you understand the details, though, it can seem quite concise. Even before version 3.0, a class with a couple of getter-only properties required very little code:

```fsharp
type Person(name, age) =
  member this.Name = name : string
  member this.Age  = age  : int
```

This uses a special shorthand for getter-only properties. The full form looks like this. Notice that the type annotations above apply to the property expressions, whereas those below apply directly to the properties. The latter is convenient when a property expression is more complex:

```fsharp
type Person(name, age) =
  member this.Name : string with get() = name 
  member this.Age  : int    with get() = age
```

The compiler determines which fields are needed. In the simplest case, it creates a field for each *primary constructor* parameter used *at least once* in a member definition. Class-level `let` bindings can also become fields. For example, the following class has two fields. The `name` parameter is used only to initialize a `let` binding, never in a member, so it does not need a field. The `mrName` binding does:

```fsharp
type MrPerson(name, age) =
  let mrName = "Mr. " + name
  member this.Name = mrName : string
  member this.Age  = age    : int
```

As a language that participates fully in the mutable, object-oriented world of .NET, F# also supports properties with both getters and setters. Primary constructor parameters are immutable, just like other F# function and method parameters, so they cannot themselves provide mutable storage. Mutable `let` bindings inside the class solve this, but the definition becomes considerably longer:

```fsharp
type MutablePerson(name, age) =
  let mutable name = name
  let mutable age  = age
  member this.Name with get() = name : string
                    and set x = name <- x
  member this.Age  with get() = age  : int
                    and set x = age <- x
```

The accessors can also be written separately:

```fsharp
type HugePerson(name, age) =
  let mutable name = name
  let mutable age  = age
  member this.Name with get() = name : string
  member this.Name with set x = name <- x
  member this.Age  with get() = age  : int
  member this.Age  with set x = age <- x
```

Accessor parameters are written explicitly, and F# supports *indexed properties*, much like VB.NET, although this feature is rarely used.

There is an even more verbose syntax for classes without a primary constructor: the type name is not followed by a parenthesized parameter list, and there are no class-level `let` bindings. Instead, fields are declared explicitly. A constructor must either call another constructor or initialize every explicitly declared field except those marked `[<DefaultValue>]`, calling a base constructor where necessary. The resulting definition is almost as verbose as its C# 2.0 equivalent:

```fsharp
type ExplicitMutablePerson =
  new (name, age) = { name = name; age = age }

  val mutable name : string
  val mutable age  : int

  member this.Name with get() = this.name
                    and set x = this.name <- x
  member this.Age with get() = this.age
                   and set x = this.age <- x
```

Unlike primary constructor parameters and class-level `let` bindings, explicit fields must be accessed through a receiver, just like other members. Here that receiver is named `this`, though each member can use a different name. Fields are immutable by default; making them mutable requires the `mutable` modifier. The immutable version with explicit fields looks like this:

```fsharp
type ExplicitImmutablePerson =
  new (name, age) = { name = name; age = age }

  val name : string
  val age  : int

  member this.Name = this.name
  member this.Age = this.age
```

This form also allows additional code to run after the object has been initialized:

```fsharp
type InstantiateMe =
  new () = { } // initialize the object
           then // perform side effects here:
             printfn "thank you!"
```

This brings us to the new auto-property syntax in F# 3.0. Getter-only auto-properties look like this:

```fsharp
type Person(name, age) =
  member val Name = name : string
  member val Age = age : int
```

The code is almost identical to the first example, but the semantics differ. With `member val`, there is no need to name a `this` parameter, and the compiler always generates a backing field. The required expression after `=` initializes the property when the object is created; it is not the body of the getter. In the following example, the string concatenation therefore happens only once per `MrPerson` instance:

```fsharp
type MrPerson(name, age) =
  member val Name = "Mr. " + name
  member val Age = age : int
```

As in C#, the backing fields are inaccessible from source code. To make these properties mutable, simply add `with get, set` after the initializer:

```fsharp
type MutablePerson(name, age) =
  member val Name = name : string with get, set
  member val Age = age : int with get, set
```

The syntax is close to C# auto-properties, though a little more verbose. However, F# can infer the types from usage in other members, and initialization is still much more compact than the explicit constructor assignments required in C#:

```c#
class MutablePerson
{
  public MutablePerson(string name, int age)
  {
    Name = name;
    Age = age;
  }

  public string Name { get; set; }
  public int Age { get; set; }
}
```

Like ordinary properties, auto-properties can be static: just add the `static` modifier. They do have some restrictions. Like class-level `let` bindings, they are allowed only in types with a primary constructor. This follows from the way F# initializes objects, a topic I hope to cover in another post.

Another restriction, which I particularly like, is that F# auto-properties cannot be virtual. This avoids the potential problem of unused backing state being left behind in a base class when a derived class overrides the property. Virtual field-like events in C# can cause [similar problems](http://blogs.msdn.com/b/samng/archive/2007/11/26/virtual-events-in-c.aspx).

Events in F# are exposed through properties. Adding `[<CLIEvent>]` tells the compiler to generate an ordinary CLR event, and the attribute also works with auto-properties:

```fsharp
type WithEvent() =
  let doneEvent = new Event<EventHandler, _>()
  [<CLIEvent>] // an auto-property exposed as an event
  member val Done = doneEvent.Publish
  member this.Complete() =
    doneEvent.Trigger(this, EventArgs.Empty)
```

This class contains two fields: one for the `Done` property and another for the `doneEvent` binding. Only `doneEvent` is really needed; using an ordinary property removes the extra field.

Unfortunately, as in F# 2.0, neither ordinary property accessors nor auto-property accessors can be annotated with attributes, unlike in C#. The backing field of an auto-property can still be annotated:

```fsharp
type Person(name: string, age: int) =
  [<field:NonSerialized>]
  member val FullName = name + string age with get
```

Auto-properties are a welcome addition to F# 3.0. They substantially reduce the boilerplate needed for mutable properties, which are often required when working with .NET libraries. The distinction between an auto-property initializer and an ordinary property's getter expression does add another detail to the already intricate rules for F# type definitions. Still, ordinary classes are needed much less often than record and union types.