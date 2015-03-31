---
layout: post
title: "F# inline & NoDynamicInvocationAttribute"
date: 2011-01-11 21:01:00
categories: 2700039671
tags: fsharp inline nodynamicinvocation generics reflection peverify csharp
---
Отвлечёмся ненадолго от монад и поговорим о такой специфичной для F# штуки, как `inline`-определения (`let`-привязки и `member`-декларации в определениях типов). Такие определения позволяют использовать в F# дополнительные ограничения на типы-параметры (*nullness constraints*, *member constraints*), оптимизировать код (засчёт принудительного встраивания кода), это некая надстройка над системой типов .NET, *специфичная только для F#*.

Интерес представляет то, как F# компилирует данные `inline`-определения в MSIL. В примере кода ниже, содержатся не представляемые нативно в MSIL операции, такие как сложение значений типа `^a` и вызов статического члена с именем `Parse` и сигнатурой `string -> ^a` для произвольного типа `^a`:

{% highlight fsharp %}
type Foo() =
     // member inline InlineAdd:
     //     ^a * ^a -> ^a when ^a: (static member (+): ^a * ^a -> ^a)
     member inline __.InlineAdd(x: ^a, y: ^a): ^a = x + y

     [<NoDynamicInvocation>]
     member inline __.NoDynAdd (x: ^a, y: ^a): ^a = x + y

     // member inline MemberConstraint:
     //     unit -> ^a when ^a: (static member Parse: string -> ^a)
     member inline __.MemberConstraint() =
            printfn "Parsing '123' string..."
            // вызов через member constraint:
            (^a: (static member Parse: string -> ^a) "123")
{% endhighlight %}

Данный код прекрасно работает, когда типы всех типов-параметров известны на момент компиляции (собственно, типы-параметры вида `^a` в F# и называются *statically resolved type variable*), через методы `InlineAdd` и `NoDynAdd` можно складывать значения любых типов, поддерживающих оператор сложения:

{% highlight fsharp %}
let foo = Foo()
let res1 = foo.InlineAdd(1, 2)
let res2 = foo.InlineAdd(1m, 2m)
let res3 = foo.NoDynAdd(1, 2)
let res4 = foo.MemberConstraint<int>()
{% endhighlight %}

Вывод:

```
Parsing '123' string...

val foo : Foo
val res1 : int = 3
val res2 : decimal = 3M
val res3 : int = 3
val res4 : int = 123
```
А теперь попробуем вызвать все эти методы через механизм рефлексии .NET, получим экземпляры `System.Reflection.MethodInfo` для всех методов:

{% highlight fsharp %}
let [ add; noDyn; memberConstr ] =
    List.map (typeof<Foo>.GetMethod) [ "InlineAdd"
                                       "NoDynAdd"
                                       "MemberConstraint" ]
{% endhighlight %}

Теперь можно вручную задать тип-параметр методу `InlineAdd` и вызвать его через рефлексию со значениями типа `int` и `decimal`:

{% highlight fsharp %}
let res1 = add.MakeGenericMethod(typeof<int>)
              .Invoke(foo, [| box 1; box 2 |])

let res2 = add.MakeGenericMethod(typeof<decimal>)
              .Invoke(foo, [| box 1m; box 2m |])
{% endhighlight %}

Вызовы происходят успешно:

```
val res1 : obj = 3
val res2 : obj = 3M
```
Метод успешно работает даже с пользовательскими типами, определяющими оператор (+) и это замечательно:

{% highlight fsharp %}
type Bar(value: int) =
     member __.Value = value
     override __.ToString() = sprintf "Bar(%d)" value
     static member (+) (l: Bar, r: Bar) = Bar(l.Value + r.Value)

let res3 = add.MakeGenericMethod(typeof<Bar>)
              .Invoke(foo, [| box (Bar 1); box (Bar 2) |])
{% endhighlight %}

А теперь попробуем произвести те же самые действия с аналогичным `inline`-методом `NoDynAdd`, отмеченным атрибутом `[<NoDynamicInvocation>]`:

{% highlight fsharp %}
let res4 = noDyn.MakeGenericMethod(typeof<int>)
                .Invoke(foo, [| box 1; box 2 |])
{% endhighlight %}

Нарываемся на исключение:

```
System.NotSupportedException: Specified method is not supported.
   at FSI_0032.Foo.NoDynAdd[a](a x, a y)
```
Всё дело в том, как F# компилирует данные методы. Метод `InlineAdd` выглядит следующим образом (C#):

{% highlight C# %}
public a InlineAdd<a>(a x, a y)
{
    return LanguagePrimitives.AdditionDynamic<a, a, a>(x, y);
}
{% endhighlight %}

Где метод `AdditionDynamic` - часть инфраструктуры среды исполнения F#, позволяющая обращаться к операторам `(+)` для различных типов, известных на момент выполнения. Если для типа `^a` оператор `(+)` определён не будет, метод `AdditionDynamic` выбросит исключение с весьма непонятным описанием:

```
System.NotSupportedException:
Dynamic invocation of op_Addition involving coercions is not supported.
```
Не трудно догадаться, что для `inline`-методов, отмеченных атрибутом `[<NoDynamicInvocation>]`, генерируются лишь заглушки, выбрасывающие исключение типа `NotSupportedException`, а само тело метода хранится лишь в метаданных F#-сборки (в любом случае):

{% highlight C# %}
[NoDynamicInvocation]
public a NoDynAdd<a>(a x, a y)
{
    throw new NotSupportedException();
}
{% endhighlight %}

А что насчёт *member constraints*? Если для некоторых встроенных операторов, F# имеет поддержку инфраструктуры во время выполнения, то для вызова произвольных методов через member constraint, пришлось бы реализовывать поддержку правил разрешения member constraints во время выполнения. Юзкейс очень редкий, реализовать оптимально сложно, поэтому F# *всегда* компилирует вызовы через member constraints как возбуждение исключения типа `NotSupportedException`:

{% highlight fsharp %}
let res5 = memberConstr.MakeGenericMethod(typeof<int>)
                       .Invoke(foo, Array.empty)
{% endhighlight %}

Однако обратите внимание на side-effect перед возбуждением исключения и тот факт, что если бы поток исполнения не дошёл бы до вызова через member constraint, то вызов метода вовсе мог бы окончиться успешно:

```
Parsing '123' string...
System.NotSupportedException: Specified method is not supported.
   at FSI_0032.Foo.MemberConstraint[a]()
```
То есть реально компилируется следующий код:

{% highlight C# %}
public a MemberConstraint<a>()
{
    ExtraTopLevelOperators.PrintFormatLine<Unit>(
        new PrintfFormat<Unit, TextWriter, Unit, Unit, Unit>("Parsing '123' string..."));
    throw new NotSupportedException();
}
{% endhighlight %}

Мораль сей басни такова, что если разрабатывая F#-библиотеку вы собираете предоставить публичные `inline`-определения, то стоит задуматься о том, что какой-нибудь злой человек может попытаться вызвать их динамически через рефлексию и что-нибудь может сломаться. Спецификация F# так же упоминает, что MSIL-код `inline`-определений может оказаться вовсе [неверифицируемым](http://www.google.com/search?hl=en&source=hp&biw=1574&bih=913&q=PEVerify&aq=f&aqi=g5g-v5&aql=&oq=&gs_rfai=). Используя атрибут `[<NoDynamicInvocation>]` вы можете запретить такие безобразия, вынуждая F# генерировать успешно верифицируемые MSIL-заглушки.