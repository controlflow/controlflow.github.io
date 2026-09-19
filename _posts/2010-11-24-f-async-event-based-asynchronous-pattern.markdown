---
layout: post
title: "F# async: event-based asynchronous pattern"
date: 2010-11-24 03:37:00
author: Aleksandr Shvedov
tags: fsharp csharp async workflow event-based asynchronous pattern
---
The [event-based asynchronous pattern](http://msdn.microsoft.com/en-us/library/wewwczdw.aspx) is a model for asynchronous programming in .NET in which an operation reports its completion through an event. Here is a simple example:

```c#
private static void AsyncDownloadGoogle()
{
  var uri = new Uri("http://google.com");
  var client = new WebClient();
  
  DownloadDataCompletedEventHandler completed = null;
  completed = (_, e) =>
  {
    // handle the operation's result
    if (e.Cancelled)
    {
      Console.WriteLine("Operation cancelled.");
    }
    else if (e.Error != null)
    {
      Console.WriteLine("Error: {0}", e.Error);
    }
    else
    {
      byte[] page = e.Result;
      Console.WriteLine("Downloaded {0} bytes", page.Length);
    }
    
    // unsubscribe from the event
    client.DownloadDataCompleted -= completed;
  };
  
  // subscribe to the completion event
  client.DownloadDataCompleted += completed;
  
  // start the asynchronous operation
  client.DownloadDataAsync(uri);
  
  // allow the user to cancel the operation
  Console.WriteLine("Press [esc] to cancel");

  var key = Console.ReadKey(true);
  if (key.Key == ConsoleKey.Escape)
  {
    client.CancelAsync();
  }
}
```

The operation's result is exposed through event arguments derived from `System.ComponentMode.AsyncCompletedEventArgs`. These arguments also indicate whether the operation was cancelled or failed. Two details require some care:

* If the same object will be reused for another asynchronous operation with a different result handler, the previous handler should be removed once the operation completes. This takes a little extra bookkeeping when the handler is an anonymous method or lambda expression, as in the example above.
* Some classes support multiple concurrent operations on the same instance, though `System.Net.WebClient` does not. To distinguish those operations, the methods used to start and cancel them need overloads that accept an additional `object userState` parameter. Completion handlers must then check the `UserState` property of the event arguments.

How can we use this pattern in F# without all the manual event handling? *F# async workflows* let us express asynchronous operations almost as concisely as synchronous ones.

To use an operation within an async workflow, however, we need a method that wraps it in an `Async<'a>` value, representing an asynchronous computation. The F# standard library provides several such extension methods for common .NET classes. It also provides `Async.FromBeginEnd()`, which creates an `Async<'a>` from a pair of Begin and End methods following the *Asynchronous Programming Model (APM)*.

The event-based asynchronous pattern has no equivalent wrapper in the standard library at the time of writing. The following two extension methods bridge that gap, adapting event-based operations to F#'s `Async<'a>` type. They also illustrate how to use `Async.FromContinuations`:

```fsharp
module AsyncExtensions

open System
open System.ComponentModel

#nowarn "40"
type Async with

  /// Convert an operation with a start method and a completion
  /// event (the event-based asynchronous pattern) into an
  /// F# asynchronous computation.
  static member FromEventPattern
      (completedEvent : IObservable<_>, // completion event
       executeAction  : unit -> unit,   // start the operation
       ?cancelAction  : unit -> unit) = // cancel the operation
    
    // start the operation with the supplied continuations
    let comp (onValue, onError, onCancel) =
      let onCancel () =
        onCancel (OperationCanceledException())
      
      // subscribe to the operation's completion event
      let rec subscription : IDisposable =
        completedEvent.Subscribe {
          new IObserver<#AsyncCompletedEventArgs> with
        
          // check the operation's status when the event fires
          member x.OnNext(args) =
            use __ = subscription // unsubscribe on exit
            if args.Cancelled then onCancel ()
            elif args.Error = null then onValue args
                                   else onError args.Error
        
          // ordinary events do not call this, but an arbitrary
          // IObservable<_> may, so handle it as well
          member x.OnError(exc) =
            use __ = subscription in onError exc
        
          member x.OnCompleted() =
            use __ = subscription in onCancel ()
        }
      
      try executeAction () // start the asynchronous operation
      with _ ->
           use __ = subscription // if starting fails,
           reraise ()            // unsubscribe immediately
    
    // create the asynchronous computation
    let operation = Async.FromContinuations comp
    
    match cancelAction with // if a cancellation action was supplied,
      | Some action ->    // register it with Async.OnCancel
             async { use! __ = Async.OnCancel action
                     return! operation }
      | None -> operation

  /// Convert an operation with a start method and a completion
  /// event (the event-based asynchronous pattern) into an
  /// F# asynchronous computation, with support for multiple
  /// concurrent operations.
  static member FromEventPattern
      (completedEvent : IObservable<_>, // completion event
       executeAction  : obj -> unit, // start the operation
       ?cancelAction  : obj -> unit, // cancel the operation
       ?userToken     : obj) =      // operation identifier

    // create an identifier if none was supplied
    let token = match userToken with Some token -> token
                                   | None -> new obj()

    // pass the identifier to the cancellation action, if any
    let cancel = Option.map (fun f () -> f token) cancelAction

    Async.FromEventPattern<#AsyncCompletedEventArgs>(
      completedEvent =      // filter completion events
          Observable.filter // by operation identifier
              (fun e -> e.UserState = token) completedEvent,
      ?cancelAction = cancel,
      executeAction = fun() -> executeAction token)
```

We can now define an extension member for `WebClient`'s `DownloadData` operation. Note the `Async` prefix, following the F# naming convention for these methods:

```fsharp
type WebClient with
  member this.AsyncDownloadData(uri: Uri) =
     Async.FromEventPattern(
       this.DownloadDataCompleted,
       (fun()-> this.DownloadDataAsync uri),
       (fun()-> this.CancelAsync()))
```

We can also transform the result so that the workflow returns the downloaded data rather than the event arguments:

```fsharp
type WebClient with
  member this.AsyncDownloadData(uri: Uri) =
    async {
      let! e = Async.FromEventPattern(
                 this.DownloadDataCompleted,
                 (fun()-> this.DownloadDataAsync uri),
                 (fun()-> this.CancelAsync()))
      
      return e.Result
    }
```

Using this extension, we can express the original example in F# as follows:

```fsharp
open System
open System.Net
open System.Threading

let asyncDownloadGoogle() =
  let uri = Uri("http://google.com")
  let client = new WebClient()
  use token = new CancellationTokenSource()
  
  let work = async {
    // handle cancellation of the async workflow
    use! cancel = Async.OnCancel (fun() ->
                        printfn "Operation cancelled.")

    // run the asynchronous operation and process its result
    try let! page = client.AsyncDownloadData(uri)
        printfn "Downloaded %d bytes" page.Length

    // handle asynchronous errors
    with e -> printfn "Error: %s" e.Message
  }

  Async.RunSynchronously(work, cancellationToken = token.Token)
  let key = Console.ReadKey true
  if (key.Key = ConsoleKey.Escape) then token.Cancel()
```

Using `CancellationTokenSource` still requires some setup, including a cancellation handler inside the workflow. In return, it provides a general cancellation mechanism, while F# propagates the token through the workflow automatically. There is no need to pass it explicitly through every asynchronous call.