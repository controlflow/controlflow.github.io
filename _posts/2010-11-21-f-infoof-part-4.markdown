---
layout: post
title: "F# infoof (part 4)"
date: 2010-11-21 04:53:00
categories: 1631819771
tags: fsharp infoof events eventof first-class events quotations pattern-matching
---
Я надеялся ограничить серию постов тремя записями, но вдруг вспомнил, что совсем забыл ещё один интересный метод – `eventof`, возвращающий экземпляр `System.Reflection.EventInfo` по выражению доступа к событию. Вот только сначала надо разобраться, что есть *«выражение доступа к событию»* в языке F#. Дело в том, что событие в CLI – это всего лишь два метода (`add_EventName` и `remove_EventName`) и метаинформация, объединяющая их.

{% highlight C# %}
class Foo
{
    public event EventHandler Completed;
}
{% endhighlight %}

Такое событие в C# вне класса `Foo` можно использовать только в выражениях добавления или удаления подписчика на событие:

{% highlight C# %}
var foo = new Foo();
foo.Completed += SomeMethodName;
foo.Completed -= SomeMethodName;
{% endhighlight %}

Однако F# поддерживает события первого класса (*first-class events*), что позволяет «материализовать» событие и пользоваться им как любым другим значением. Например, определим в F# новый тип с двумя событиями - CLI-совместимым событием `Bar` и обычным событием F# `Baz`:

{% highlight fsharp %}
type Foo() =
     let bar = Event<int>()
     let baz = Event<int>()

     [<CLIEvent>]
     member __.Bar = bar.Publish
     member __.Baz = baz.Publish
{% endhighlight %}

Теперь, например, можно сложить оба события в список и подписаться на них в цикле:

{% highlight fsharp %}
for e in [ foo.Bar; foo.Baz ] do
    e.AddHandler(fun _ _ -> printfn "!")
{% endhighlight %}

Вопрос в том, что собой представляют выражения `foo.Bar` и `foo.Baz`, а ответит на этот вопрос система цитирования F#:

{% highlight fsharp %}
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
{% endhighlight %}

Ага, свойства F# - это всего лишь обычные CLI-свойства, возвращающие объекты типа `IEvent`, а вот для обычных CLI-событий F# генерирует по месту обращения вызов скрытого метода `CreateEvent` из стандартной библиотеки F#. Данный метод возвращает объект типа `IEvent`, получая несколько анонимных функций, предназначенных для подписки и отписки от события. То есть F# позволяет единообразно работать с любыми событиями, как с первоклассными сущностями типа `IEvent`, при этом компилятор скрывает процесс обёртки пары `add`/`remove`-методов в `IEvent`.

Вернёмся к исходной задаче – получение экземпляра `EventInfo`. Так как `EventInfo` генерируется только для CLI-совместимых событий, то всё, что нам надо сделать – научиться доставать пару `add`/`remove`-методов из генерируемой F# обёртки, и по этой паре извлекать из типа экземпляр объекта `EventInfo`. Попробуем:

{% highlight fsharp %}
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
               addHandler.Name.Remove(0, 4), // имя события
               BindingFlags.Public ||| BindingFlags.Instance |||
               BindingFlags.Static ||| BindingFlags.NonPublic)

    | _ -> failwith "Not a event expression"
{% endhighlight %}

То есть ищем вызов метода с именем `CreateEvent`, получающего три анонимных функции в качестве параметров, две из которых содержат внутри вызов методов с именами, начинающимися на `add_` и `remove_`. Далее из имени метода подписки выделяется имя события, путём удаления префикса `add_` в начале строки и производится поиск в типе, определяющим метод подписки, событие с данным именем. Проверяем:

{% highlight fsharp %}
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
{% endhighlight %}