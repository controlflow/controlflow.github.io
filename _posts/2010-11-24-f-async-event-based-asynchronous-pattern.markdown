---
layout: post
title: "F# async + event-based asynchronous pattern"
date: 2010-11-24 03:37:00
categories: 1663779524
tags: fsharp csharp async workflow event-based asynchronous pattern
---
Привет всем.

Сегодня предлагаю поговорить о модели асинхронного программирования в .NET, основанной на событиях ([event-based asynchronous pattern](http://msdn.microsoft.com/en-us/library/wewwczdw.aspx)). Если вкратце, то всё очень просто:

{% highlight C# %}
static void AsyncDownloadGoogle()
{
    var uri = new Uri("http://google.com");
    var client = new WebClient();

    DownloadDataCompletedEventHandler completed = null;
    completed = (_, e) =>
    {
        // обрабатываем результат операции
        if (e.Cancelled)
        {
            Console.WriteLine("Операция отменена!");
        }
        else if (e.Error != null)
        {
            Console.WriteLine("Ошибка: {0}", e.Error);
        }
        else
        {
            byte[] page = e.Result;
            Console.WriteLine("Загружено {0} байт", page.Length);
        }

        // отписка от события
        client.DownloadDataCompleted -= completed;
    };

    // подписываемся на результат операции
    client.DownloadDataCompleted += completed;

    // запускаем асинхронную операцию
    client.DownloadDataAsync(uri);

    // даём возможность отменить операцию
    Console.WriteLine("Нажмите [esc] для отмены");
    var key = Console.ReadKey(true);
    if (key.Key == ConsoleKey.Escape)
    {
        client.CancelAsync();
    }
}
{% endhighlight %}

То есть основа паттерна – получения результатов асинхронной операции через аргументы события (наследник класса `System.ComponentModel .AsyncCompletedEventArgs`), при этом существует возможность определить, что операция была отменена или завершена с ошибкой. Нюансы возникают в двух случаях:

* Если экземпляр класса, предоставляющего асинхронную операцию, планируется переиспользовать и результаты обрабатывать другим обработчиком, то следует отписывать обработчики после завершения операции (что может приводить к лишним телодвижениям, если вы подписываетесь анонимным методом или лямбда-выражением, как в примере выше).
* Экземпляр класса, предоставляющий асинхронную операцию, может допускать одновременное исполнение некоторой операции (класс `System.Net.WebClient`, к сожалению, не из таких). В этом случае все методы (запуск, отмена асинхронной операции) должны обладать перегрузками, принимающими дополнительный параметр вида `object userState`, который позволяет отличать независимые операции друг от друга (обработчики результатов должны проверять значение свойства `UserState` в аргументе события).

Возникает вопрос, как всё это дело использовать в F# и обязательно ли асинхронные операции должны выглядеть так же ущербно? На помощь приходят *F# async workflows*, позволяющие записывать асинхронные операции так же лаконично, как синхронные.

Однако, чтобы использовать асинхронные операции внутри async workflow, требуются специальные метод, запускающие асинхронные операции и возвращающие объекты типа `Async<’a>`, представляющие собой некое асинхронное вычисление. В стандартную библиотеку F# входит несколько методов-расширений подобного рода, предназначенных для некоторых стандартных классов .NET, а так же метод `Async.FromBeginEnd()` позволяющие получить `Async<’a>` из асинхронных операций, заданных в виде пары методов Begin и End (старый добрый *APM-шаблон*).

Я это всё к тому, что *event-based asynchronous pattern* конечно же забыли, поэтому предлагаю вашему вниманию пару методов-расширений, предназначенных для преобразования асинхронных операций, выполненных в рамках данного паттерна, в родной для F# тип `Async<’a>` (получился неплохой пример применения метода `Async.FromContinuations`, надеюсь, комментариев будет достаточно):

{% highlight fsharp %}
module AsyncExtensions

open System
open System.ComponentModel

#nowarn "40"
type Async with

  /// Преобразует асинхронную операцию, заданную в виде метода
  /// запуска и события завершения (event-based asynchronous
  /// pattern) в асинхронное вычисление F# async
  static member FromEventPattern
        (completedEvent : IObservable<_>, // событие завершения
         executeAction  : unit -> unit,      // запуск операции
         ?cancelAction  : unit -> unit) =    // отмена операции

    // функция запуска асинхронной операции
    let comp (onValue, onError, onCancel) =
        let onCancel () =
            onCancel (OperationCanceledException())

        // подписываемся на событие завершения операции
        let rec subscription : IDisposable =
            completedEvent.Subscribe {
              new IObserver<#AsyncCompletedEventArgs> with

              // если событие было возбуждено, проверяем статус
              member x.OnNext(args) =
                use __ = subscription // отписываемся при выходе
                if args.Cancelled then onCancel ()
                elif args.Error = null then onValue args
                                       else onError args.Error

              // для обычных событий никогда не будет вызываться,
              // но для любых IObservable<_> лучше предусмотреть
              member x.OnError(exc) =
                use __ = subscription in onError exc

              member x.OnCompleted() =
                use __ = subscription in onCancel ()
            }

        try executeAction () // и запускаем асинхронную операцию
        with _ ->
             use __ = subscription // если запуск упадёт,
             reraise ()            // то сразу отписываемся

    // формируем асинхронное вычисление
    let operation = Async.FromContinuations comp

    match cancelAction with // если указали метод отмены,
        | Some action ->    // то оборачиваем в Async.OnCancel
               async { use! __ = Async.OnCancel action
                       return! operation }
        | None -> operation

  /// Преобразует асинхронную операцию, заданную в виде метода
  /// запуска и события завершения (event-based asynchronous
  /// pattern) и поддерживающую несколько одновременных вызовов
  /// в асинхронное вычисление F# async
  static member FromEventPattern
        (completedEvent : IObservable<_>, // событие завершения
         executeAction  : obj -> unit, // ф-ция запуск операции
         ?cancelAction  : obj -> unit, // ф-ция отмены операции
         ?userToken     : obj) =      // идентификатор операции

    // если идентификатор операции не задан, то создаём новый
    let token = match userToken with Some token -> token
                                   | None -> new obj()

    // если задан метод отмены операции
    let cancel = Option.map (fun f () -> f token) cancelAction

    Async.FromEventPattern<#AsyncCompletedEventArgs>(
        completedEvent =      // фильтруем события
            Observable.filter // по идентификатору
                (fun e -> e.UserState = token) completedEvent,
        ?cancelAction = cancel,
        executeAction = fun() -> executeAction token)
{% endhighlight %}

Теперь можно очень легко определить тип-расширение для операции `DownloadData` класса `WebClient` (обратите внимание на соглашение об именовании подобных методов – префикс `Async`):

{% highlight fsharp %}
type WebClient with
     member this.AsyncDownloadData(uri: Uri) =
        Async.FromEventPattern(
            this.DownloadDataCompleted,
            (fun()-> this.DownloadDataAsync uri),
            (fun()-> this.CancelAsync()))
{% endhighlight %}

Можно дополнительно преобразовывать результат операции, доставая из аргументов события результат операции:

{% highlight fsharp %}
type WebClient with
     member this.AsyncDownloadData(uri: Uri) =
        async {
           let! e = Async.FromEventPattern(
                      this.DownloadDataCompleted,
                      (fun()-> this.DownloadDataAsync uri),
                      (fun()-> this.CancelAsync()))

           return e.Result
        }
{% endhighlight %}

Теперь исходный пример можно выразить на F# следующим образом:

{% highlight fsharp %}
open System
open System.Net
open System.Threading

let asyncDownloadGoogle() =
    let uri = Uri("http://google.com")
    let client = new WebClient()
    use token = new CancellationTokenSource()

    let work = async {
        // обработчик отмены async workflow
        use! cancel = Async.OnCancel (fun() ->
                            printfn "Операция отменена!")

        // вызов асинхронной операции и работа с результатом
        try let! page = client.AsyncDownloadData(uri)
            printfn "Загружено %d байт" page.Length

        // обработка асинхронных ошибок
        with e -> printfn "Ошибка: %s" e.Message
    }

    Async.RunSynchronously(work, cancellationToken = token.Token)
    let key = Console.ReadKey true
    if (key.Key = ConsoleKey.Escape) then token.Cancel()
{% endhighlight %}

Использование `CancellationTokenSource` выглядит не очень симпатично (определение обработчика внутри workflow), однако это мощный и обобщённый механизм отмены асинхронных операций, при этом от пользователя скрывается передача токена по всему workflow, что существенно упрощает код.