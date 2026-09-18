---
layout: post
title: "F# infoof operator (part 3)"
date: 2010-11-20 18:51:00
author: Aleksandr Shvedov
tags: fsharp infoof events eventof first-class events quotations pattern-matching
---
With properties and methods covered, we can turn to events. The `eventof` helper returns a `System.Reflection.EventInfo` from an event access expression. First, we need to understand what an *event access expression* means in F#. A CLI event is represented by its `add_EventName` and `remove_EventName` methods, together with metadata that associates them:

```c#
class Foo
{
  public event EventHandler Completed;
}
```

In C#, code outside `Foo` can use this event only to subscribe or unsubscribe a handler:

```c#
var foo = new Foo();
foo.Completed += SomeMethodName;
foo.Completed -= SomeMethodName;
```

F# supports *first-class events*, so an event can be represented as a value and used like any other value. For example, this F# type defines two events: a CLI-compatible event named `Bar` and an ordinary F# event named `Baz`:

```fsharp
type Foo() =
  let bar = Event<int>()
  let baz = Event<int>()

  [<CLIEvent>]
  member __.Bar = bar.Publish
  member __.Baz = baz.Publish
```

Given an instance named `foo`, we can put both events in a list and subscribe to them in a loop:

```fsharp
for e in [ foo.Bar; foo.Baz ] do
  e.AddHandler(fun _ _ -> printfn "!")
```

What do the expressions `foo.Bar` and `foo.Baz` represent? Their quotations show the difference:

```fsharp
let foo = Foo()

<@ foo.Bar @>
   Call (None,
      IEvent`2[...] CreateEvent[FSharpHandler`1,Int32](...),
      [Lambda (eventDelegate,
               Call (Some foo,
                     Void add_Bar(FSharpHandler`1[Int32]),
                     [eventDelegate])),
       Lambda (eventDelegate,
               Call (Some foo,
                     Void remove_Bar(FSharpHandler`1[Int32]),
                     [eventDelegate])),
       Lambda (callback,
               NewDelegate (FSharpHandler`1[Int32],
                            [ a1; a2 ],
                            Application (
                               Application (callback, a1), a2)))])

<@ foo.Baz @>
   PropertyGet (Some foo,
                IEvent`2[FSharpHandler`1[Int32],Int32] Baz, [])
```

An ordinary F# event such as `Baz` is exposed as a CLI property returning an `IEvent` object. For a CLI event such as `Bar`, however, F# generates a call to the standard library's internal `CreateEvent` helper at the point of access. This helper constructs an `IEvent` from functions that subscribe and unsubscribe handlers, together with a function that creates the appropriate delegate. F# can therefore present both forms uniformly as first-class `IEvent` values, while the compiler handles the wrapping of the CLI event's `add` and `remove` accessors.

Returning to `eventof`, only CLI-compatible events have corresponding `EventInfo` metadata. We need to extract their accessors from the generated wrapper and use that information to find the event on the declaring type:

```fsharp
let eventof expr =
  match expr with
  | Call(None, createEvent, [
          Lambda(arg1, Call(_,    addHandler, [ Var var1 ]))
          Lambda(arg2, Call(_, removeHandler, [ Var var2 ]))
          Lambda(_, NewDelegate _)
        ])
    when createEvent.Name = "CreateEvent"
      &&    addHandler.Name.StartsWith("add_")
      && removeHandler.Name.StartsWith("remove_")
      && arg1 = var1
      && arg2 = var2 ->
         addHandler.DeclaringType.GetEvent(
             addHandler.Name.Remove(0, 4), // Event name.
             BindingFlags.Public ||| BindingFlags.Instance |||
             BindingFlags.Static ||| BindingFlags.NonPublic)

  | _ -> failwith "Not an event expression"
```

The pattern looks for a call named `CreateEvent` with three lambda arguments. The first two must call methods whose names begin with `add_` and `remove_`, passing their respective lambda parameters as the handler arguments. The event name is then obtained by removing the `add_` prefix, and `GetEvent` looks it up on the type that declares the add accessor. For example:

```fsharp
eventof<@ foo.Bar @>

val it : EventInfo =
  FSharpHandler`1[System.Int32] Bar
    {Attributes = None;
     DeclaringType = Foo;
     EventHandlerType = FSharpHandler`1[System.Int32];
     IsMulticast = true;
     MemberType = Event;
     Name = "Bar";
     ...}
```

In the final post, we will bring these helpers together into the complete `MemberInfo` module, adding support for fields, constructors, and discriminated union cases.