---
layout: post
title: "F# events + lock-free + async (updated)"
date: 2010-10-21 02:05:00
categories: 1361833918
tags: fsharp events delegate lock-free subscription
---
Сегодня речь пойдёт о механизме событий в F#. Не смотря на то, что F# обладает такой замечательно штукой, как события первого класса, мне не очень понравилось как организована работа с событиями внутри.

Для того чтобы на события определённых в F# типов смогли подписываться из других CLI-языков приходится использовать тормозной `DelegateEvent`, вызывающий делегат с подписчиками через рефлексию. Данную проблему хорошо описал в своём блоге Владимир Матвеев: ["F# performance of events"](http://v2matveev.blogspot.com/2010/06/f-performance-of-events.html) (+ [update](http://v2matveev.blogspot.com/2010/06/f-performance-of-events-update.html)). Проблема заключается в вызове делегата в обобщённом коде, кода тип делегата является параметризуемым. Владимир предложил решение проблемы с помощью кодогенерации или F# member constraints, однако существует ещё более простой и наименее ресурсоёмкий способ (как оказалось, Владимир обнаружил этот способ [раньше меня](http://rsdn.ru/forum/decl/3979546.1.aspx)).

Используя великолепный метод `Delegate.CreateDelegate`, можно создать делегат из экземплярного метода `Invoke()` любого типа делегата таким образом, что `this` для вызова метода `Invoke()` можно будет передавать в качестве первого параметра получаемого делегата, то есть фактически сделать статический метод из экземплярного. Таким образом можно получить делегат-invoker экземпляров делегатов любого типа, не применяя какую-либо кодогенерацию и отказавшись от излишнего копирования кода `inline`-методов при решении проблемы с помощью member constraints (гляньте Reflector’ом, если хотите ужаснуться).

Ещё одну проблему составляет тот факт, что в отличие от C#, процесс подписки и отписки на события, создаваемые с помощью входящих в стандартную библиотеку F# класоов `Event` и `DelegateEvent`, не является синхронизованным. До верcии 4.0, компилятор C# оборачивал тела акцессоров, генерируемых для field-like events, в блоки `lock(this) { }` (в статических событиях - `lock(typeof(Класс)) { }`). Начиная с версии C# 4.0 в акцессорах событий генерируется код lock-free подписки. А чем F# хуже?

Ко всему прочему, [@cadet354](https://twitter.com/cadet354) предложил включить в событие функционал для асинхронного вызова подписчиков (ведь действительно, часто совершенно не обязательно дожидаться окончания их работы), а так же параллельного вызова подписчиков (к примеру, используя инфраструктуру F# async). Я не считаю эти сценарии слишком распространёнными, но почему бы и не предусмотреть их.

А вот и набросок класса, решаюшего обе проблемы:

{% highlight fsharp %}
open System
open System.Threading

[<Sealed>]
type PowerEvent<'del, 'args
     when 'del :  not struct                  // ссылочный тип
      and 'del :  delegate<'args, unit>  // сигнатура делегата
      and 'del :> Delegate        // наследник System.Delegate
      and 'del :  null>() =         // принимает значение null

  [<DefaultValue>]
  val mutable private target : 'del

  // Создание инвокатора делегатов типа 'del
  static let invoker : Action<_,_,_> =
    downcast Delegate.CreateDelegate(
      typeof<Action<'del, obj, 'args>>, typeof<'del>.GetMethod "Invoke")

  // Триггер события
  member self.Trigger (sender: obj, args: 'args) =
     match self.target with
     null    -> ()
   | handler -> invoker.Invoke (handler, sender, args)

  // Асинхронный триггер события
  member self.TriggerAsync (sender: obj, args: 'args) =
     match self.target with
     null    -> ()
   | handler ->
         async { invoker.Invoke (handler, sender, args) }
         |> Async.Start

  // Асинхронный параллельный триггер события
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

  // Чтобы не создавать экземпляр IDelegateEvent<'del>
  // на каждый факт подписки/отписки на событие, можно
  // реализовать интерфейс для просто подписки здесь:
  interface IDelegateEvent<'del> with

     member self.AddHandler handler =
       self.target <- downcast Delegate.Combine (self.target, handler)

     member self.RemoveHandler handler =
       self.target <- downcast Delegate.Remove (self.target, handler)

  // Публикация события без синхронизации подписки/отписки
  member self.Publish = self :> IDelegateEvent<'del>

  // Публикация события c синхронизацией подписки/отписки
  member self.PublishSync =
   { new IDelegateEvent<'del> with

     member __.AddHandler handler =
       lock self (fun() ->
            self.target <- downcast Delegate.Combine (self.target, handler))

     member __.RemoveHandler handler =
       lock self (fun() ->
            self.target <- downcast Delegate.Remove (self.target, handler)) }

  // Публикация события c механизмом
  // lock-free синхронизации подписки/отписки
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
{% endhighlight %}

Данный класс предлагает несколько политик синхронизации подписки:

* Без синхронизации вовсе
* Синхронизация с помощью lock (аналогично C# 3.5 и младше)
* Lock-free синхронизация (аналогично C# 4.0)

А так же несколько политик возбуждения событий:

* Синхронно (последовательные вызовы подписчиков, ожидание окончания их работы)
* Асинхронно (последовательные вызывы подписчиков, но в другом потоке и не дожидаясь окончания их работы)
* Асинхронно и по возможности параллельно (не ожидая окончания работы подписчиков на событие)

Использовать практически так же, как обычные события F#:

{% highlight fsharp %}
type Foo() =
    let event = PowerEvent<EventHandler, _>()

    member self.Fire() = event.Trigger (self, EventArgs.Empty)

    [<CLIEvent>] member this.Event1 = event.Publish
    [<CLIEvent>] member this.Event2 = event.PublishSync
    [<CLIEvent>] member this.Event3 = event.PublishLockFree
{% endhighlight %}

К сожалению, серъёзному тестированию код не подвергался, так что используйте на свой страх и риск.