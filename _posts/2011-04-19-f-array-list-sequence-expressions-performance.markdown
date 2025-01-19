---
layout: post
title: "F# array/list sequence expressions performance"
date: 2011-04-19 20:00:00
author: Aleksandr Shvedov
tags: fsharp fprog computation expressions builders lists arrays list comprehensions seq
---
Изучая разделы 6.3.13 и 6.3.14 [спецификации F#](http://research.microsoft.com/en-us/um/cambridge/projects/fsharp/manual/spec.html), я обнаружил следующие утверждения относительно вычисления выражений созданий списков `[ ]` и массивов `[| |]` (так называемые *list comprehensions*):

* In all cases `[ cexpr ]` elaborates to `Microsoft.FSharp.Collections.Seq.toList(seq { cexpr })`.
* In all cases `[| cexpr |]` elaborates to `Microsoft.FSharp.Collections.Seq.toArray(seq { cexpr })`.

Что меня немного удивило. Дело в том, что списки и массивы по своей природе фундаментально отличаются от `seq`-последовательностей, которые обладают свойством ленивости. Ленивость `seq`-последовательностей вынуждает компилятор генерировать достаточно большую “портянку”, а именно - конечный автомат (аналогично `yield return`-итераторам в C#), который разбивает выражение генерирования `seq`-последовательности на состояния, при этом все переменные внутри выражения хранятся в замыкании.

Всё это - абсолютно разумный оверхед, неободимый для поддержки ленивости. Но что насчёт массивов и списков? Знакомясь с F#, я почему-то был абсолютно уверен, что `[ ]` и `[| |]` отличаются по генерируемому коду от `seq { }` в положительную сторону, так как им вовсе не нужна инфраструктура отложенности, однако спецификация убедила в обратном…

Стало интересно преодолеть как-либо данную проблему и придумалось реализовать свой *builder*-класс для computation expression, создающий списки и массивы в энергичном порядке. Вообще говоря, в F# все computation expressions компилируются в вызовы методов соответствующих builder-классов с передачей тьмы вложенных лямбда-выражений. Но есть одно исключение - выражения `seq { }` - для них F# генерирует более оптимальную реализацию на основе конечного автомата. Неужели можно обогнать оптимизированную, но отложенную реализацию `seq { }`?

Оказывается, что можно. В этом нам поможет тот факт, что ключевое слово `inline` в F# позволяет определять не только встраиваемые `let`-определения, но и `member`-декларации. Определяя методы builder-класса как `inline`, можно устранить множество лямбда-выражений (но не все) и получить генерацию практически императивного код формирования списка/массива безо всякой отложенности. Сначала я реализовал `[| |]`, используя обычный класс `List<’T>` из состава .NET Framework:

```fsharp
type FastArrayBuilder<'a>() =
  inherit System.Collections.Generic.List<'a>()

type FastArrayBuilder<'a> with
  member inline arr.Yield(x)       = arr.Add(x)
  member inline arr.YieldFrom(xs)  = arr.AddRange(xs)
  member inline arr.Run(f)         = f(); arr.ToArray()
  member inline arr.Combine((), f) = f()
  member inline arr.Delay(f)       = f
  member inline arr.Zero()         = ()
  member inline arr.For(seq, f)    = for x in seq do f x
  member inline arr.Using(expr, f) = use e = expr in f e
  member inline arr.While(cond, f) = while cond() do f()
  member inline arr.TryWith(t, f)  = try t() with e -> f()
  member inline arr.TryFinally(t, f) = try t() finally f()

let inline fastarray<'a> = FastArrayBuilder<'a>()
```

Обратите внимание, что builder-класс непосредственно является наследником `List<’T>` (!), а все его члены определены в расширении типа - это необходимо из-за того, что F# не допускает использование публичных членов, унаследованных от CLI-типов, в `inline`-определениях (возможно это и баг), а вот вариант с type extension вполне работает. Ещё следует обратить внимание на то, что `fastarray` является *[type function]({{ site.baseurl }}/2010/11/01/f-type-functions.html)* - это нужно, чтобы построение каждого `fastarray`-выражения начиналось с нового пустого `List<’T>`-списка. Каждое обращение к *значению*` fastarray` компилируется как новое вычисление выражения `FastArrayBuilder<’a>()` - то есть создание нового экземпляра списка.

Давайте сравним производительность в “полевых” условиях, генерируя массивы достаточно сложным выражением (к сожалению, дублирование кода тут избежать не удастся):

```fsharp
Measure.run [

  "[| |]", fun() ->
    [|
      yield 1; yield 2; yield! {3 .. 4}
      let x1 = 123
      try for i = 1 to 10 do
            if i < 5 then yield i
                          yield! [ x1 ]
            else yield! [| 1; 2; i |]
          yield 777
      finally ()
      for i in 0 .. 10 do
        if i % 2 = 0 then yield! [1]
      yield 99
    |]
    |> ignore

  "fastarray { }", fun() ->
    fastarray {
      yield 1; yield 2; yield! {3 .. 4}
      let x1 = 123
      try for i = 1 to 10 do
            if i < 5 then yield i
                          yield! [ x1 ]
            else yield! [| 1; 2; i |]
          yield 777
      finally ()
      for i in 0 .. 10 do
        if i % 2 = 0 then yield! [1]
      yield 99
    }
    |> ignore
]
```

Результаты получились следующими (на разных выражениях я получал прирост от 1.5 до 3 раз по сравнению с `[| |]`-выражениями), обратите внимание на количество сборок мусора (последний столбец):

![]({{ site.baseurl }}/images/fsharp-array-seq.png)

Окей, что насчёт такой основы F#, как списки? `[]`-выражения тоже базируются на `seq { }`, попробуем написать замену:

```fsharp
[<Struct>]
type FastListBuilder<'a> =
  new _ = { tail = [] }
  val mutable tail : 'a list

  member inline list.Yield(x) =
    list.tail <- x :: list.tail
  member inline list.YieldFrom(xs) =
    for x in xs do list.tail <- x :: list.tail
  member inline list.Run(f) =
    f(); List.rev list.tail

  member inline list.Combine((), f) = f()
  member inline list.Delay(f)       = f
  member inline list.Zero()         = ()
  member inline list.For(seq, f)    = for x in seq do f x
  member inline list.Using(expr, f) = use e = expr in f e
  member inline list.While(cond, f) = while cond() do f()
  member inline list.TryWith(t, f)  = try t() with e -> f()
  member inline list.TryFinally(t, f) = try t() finally f()

let inline fastlist<'a> = FastListBuilder<'a>(1)
```

Реализация существенно отличается от приведенной ранее. Теперь для builder’а используется значимый тип (меньше indirections), который хранит изменяемую ссылку на конец собранного списка, которую подменяет каждые `yield` и `yield!`. К сожалению, список собирается в обратном порядке, поэтому при запуске выражения его приходится переворачивать (если бы это был код стандартной библиотеки F#, то можно было бы мутировать список и собирать его в нужном порядке, но в пользовательском коде такой возможности нет). Тест:

```fsharp
Measure.run [

  "[ ]", fun() ->
    [
      yield 1; yield 2; yield! {3 .. 4}
      let x1 = 123
      try for i = 1 to 10 do
            if i < 5 then yield i
                          yield! [ x1 ]
            else yield! [| 1; 2; i |]
          yield 777
      finally ()
      for i in 0 .. 10 do
        if i % 2 = 0 then yield! [1]
      yield 99
    ]
    |> ignore

  "fastlist { }", fun() ->
    fastlist {
      yield 1; yield 2; yield! {3 .. 4}
      let x1 = 123
      try for i = 1 to 10 do
            if i < 5 then yield i
                          yield! [ x1 ]
            else yield! [| 1; 2; i |]
          yield 777
      finally ()
      for i in 0 .. 10 do
        if i % 2 = 0 then yield! [1]
      yield 99
    }
    |> ignore
]
```

Не смотря на разворот списка, результаты радуют (более чем в 2 раза меньше сборок мусора в первом поколении):

![]({{ site.baseurl }}/images/fsharp-array-seq2.png)

Если вам кажется, что выигрыш не оправдан, то задумайтесь - неизменяемые списки - это основа функционального языка, которым является F#. Такие фундаментальные возможности языка, как генераторы списков, просто обязаны работать настолько быстро, насколько это возможно.

p.s. Однако всё же есть сценарии, в которых нынешняя кодогенерация через `seq { }` будет оправдана. А вы знаете в каких случаях? :))