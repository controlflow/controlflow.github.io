---
layout: post
title: "F# events: lock-free subscription & async firing"
date: 2010-10-21 02:05:00
author: Aleksandr Shvedov
tags: fsharp events delegate lock-free subscription
---
F# provides first-class events, but I found a few limitations in their implementation that are worth examining.

To expose events on F# types to subscribers written in other CLI languages, the standard approach uses `DelegateEvent`, which invokes its handlers through reflection. Vladimir Matveev describes the resulting performance problem in ["F# performance of events"](http://v2matveev.blogspot.com/2010/06/f-performance-of-events.html) and its [update](http://v2matveev.blogspot.com/2010/06/f-performance-of-events-update.html). The difficulty is invoking a delegate from generic code when its type is itself a type parameter. Vladimir proposed solutions using code generation or F# member constraints, but there is a simpler approach with less overhead. It turned out that he had also [discovered this approach before I did](http://rsdn.ru/forum/decl/3979546.1.aspx).

`Delegate.CreateDelegate` can create an open instance delegate for a delegate type's `Invoke()` method. The first argument to the resulting delegate supplies the receiver that would normally be passed as `this`. This gives us a typed invoker for instances of the chosen delegate type, without generating code or duplicating the bodies of `inline` methods as the member-constraint approach can do.

Another limitation is that the F# standard library's `Event` and `DelegateEvent` classes do not synchronize subscription and unsubscription. By comparison, before C# 4.0, the C# compiler synchronized the accessors generated for field-like events using `lock(this)` for instance events and `lock(typeof(ContainingType))` for static events. Starting with C# 4.0, it generates lock-free subscription code instead. Both approaches can also be implemented in F#.

[@cadet354](https://twitter.com/cadet354) also suggested supporting asynchronous invocation, for cases where the caller does not need to wait for handlers to finish, and parallel invocation using F# async workflows. These options may be useful even if they are less common than synchronous event delivery.

The following prototype combines these invocation and subscription options:

```fsharp
open System
open System.Threading

[<Sealed>]
type PowerEvent<'del, 'args
     when 'del :  not struct             // reference type
      and 'del :  delegate<'args, unit>  // delegate signature
      and 'del :> Delegate               // derives from System.Delegate
      and 'del :  null>() =              // supports null

  [<DefaultValue>]
  val mutable private target : 'del

  // create an invoker for delegates of type 'del
  static let invoker : Action<_,_,_> =
    downcast Delegate.CreateDelegate(
      typeof<Action<'del, obj, 'args>>, typeof<'del>.GetMethod "Invoke")

  // invoke the event handlers synchronously
  member self.Trigger (sender: obj, args: 'args) =
     match self.target with
     null    -> ()
   | handler -> invoker.Invoke (handler, sender, args)

  // invoke the event handlers asynchronously
  member self.TriggerAsync (sender: obj, args: 'args) =
     match self.target with
     null    -> ()
   | handler ->
         async { invoker.Invoke (handler, sender, args) }
         |> Async.Start

  // invoke the event handlers asynchronously, allowing parallel execution
  member self.TriggerParallel (sender: obj, args: 'args) =
     match self.target with
     null    -> ()
   | handler ->
         handler.GetInvocationList ()
      |> Array.map (fun h -> async {
           invoker.Invoke (downcast h, sender, args)
         })
      |> Async.Parallel
      |> Async.Ignore
      |> Async.Start

  // to avoid creating an IDelegateEvent<'del> wrapper
  // for every subscription or unsubscription, implement
  // the unsynchronized interface directly here:
  interface IDelegateEvent<'del> with

     member self.AddHandler handler =
       self.target <- downcast Delegate.Combine (self.target, handler)

     member self.RemoveHandler handler =
       self.target <- downcast Delegate.Remove (self.target, handler)

  // expose the event without synchronizing subscription changes
  member self.Publish = self :> IDelegateEvent<'del>

  // expose the event with lock-based subscription changes
  member self.PublishSync =
   { new IDelegateEvent<'del> with

     member __.AddHandler handler =
       lock self (fun() ->
            self.target <- downcast Delegate.Combine (self.target, handler))

     member __.RemoveHandler handler =
       lock self (fun() ->
            self.target <- downcast Delegate.Remove (self.target, handler)) }

  // expose the event with lock-free
  // synchronization of subscription changes
  member self.PublishLockFree =
   { new IDelegateEvent<'del> with

     member __.AddHandler handler =
       let rec loop o =
         let c = downcast Delegate.Combine (o, handler)
         let r = Interlocked.CompareExchange(&self.target,c,o)
         if obj.ReferenceEquals (r, o) = false then loop r
       loop self.target

     member __.RemoveHandler handler =
       let rec loop o =
         let c = downcast Delegate.Remove (o, handler)
         let r = Interlocked.CompareExchange(&self.target,c,o)
         if obj.ReferenceEquals (r, o) = false then loop r
       loop self.target }
```

The class offers three ways to manage subscriptions:

* Without synchronization
* With locking, as in C# versions before 4.0
* With lock-free synchronization, as in C# 4.0

It also provides three ways to invoke the handlers:

* Synchronously: invoke handlers in sequence and wait for them to finish.
* Asynchronously: invoke handlers in sequence on another thread, without waiting for them to finish.
* Asynchronously with parallel execution where possible, without waiting for the handlers to finish.

Usage is similar to ordinary F# events:

```fsharp
type Foo() =
    let event = PowerEvent<EventHandler, _>()

    member self.Fire() = event.Trigger (self, EventArgs.Empty)

    [<CLIEvent>] member this.Event1 = event.Publish
    [<CLIEvent>] member this.Event2 = event.PublishSync
    [<CLIEvent>] member this.Event3 = event.PublishLockFree
```

This is a prototype and has not been thoroughly tested.