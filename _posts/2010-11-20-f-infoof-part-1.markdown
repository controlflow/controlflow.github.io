---
layout: post
title: "F# infoof (part 1)"
date: 2010-11-20 04:15:00
categories: 1622690381
tags: fsharp infoof quotations patterns pattern-matching
---
Сегодня предлагаю обсудить такие элементы F#, как совпадение с образцом (*pattern matching*) и активные образцы F# (*active patterns*), которые незаменимы, при работе с цитированием кода (*F# quotations*). В качестве задания, попробуем написать набор функций, логически похожих на `typeof<T>` и предназначенных получения различных наследников `System.Reflection.MemberInfo` для заданных свойств, методов, функций, конструкторов и прочих элементов кода. То есть напишем на F# аналог несуществующего оператора `infoof()` (читай *info-of*), аналоги которого все кому не лень, реализуют в C# на базе *Expression Trees*, например, [вот](http://codebetter.com/blogs/patricksmacchia/archive/2010/06/28/elegant-infoof-operators-in-c-read-info-of.aspx) (обсуждение Эрика Липперта [здесь](http://blogs.msdn.com/b/ericlippert/archive/2009/05/21/in-foof-we-trust-a-dialogue.aspx)).

Давайте попробуем описать простую функцию, получающую процитированное выражение F# и возвращающую объект типа `System.Reflection.PropertyInfo` в случае, если переданное выражение является выражением доступа к свойству:

{% highlight fsharp %}
open Microsoft.FSharp.Quotations.Patterns

let propertyof expr =
  match expr with
    | PropertyGet(_, info, _) -> info
    | _ -> failwith "Not a property expression"
{% endhighlight %}

Всё, что делает данная функция – использует «активный образец» (или «активный шаблон», *active pattern*) из модуля `Microsoft.FSharp.Quotations.Patterns` для попытки извлечения выражения доступа к свойству. Функцию легко использовать для получения `PropertyInfo` статических свойств и свойств различных переменных и литералов, доступных в контексте вызова `propertyof`:

{% highlight fsharp %}
propertyof<@ (null : string).Length @>

val it : System.Reflection.PropertyInfo =
  Int32 Length {Name = "Length";
                CanRead = true;
                CanWrite = false;
                DeclaringType = System.String;
                PropertyType = System.Int32; ...}

propertyof<@ System.Console.CapsLock @>

val it : System.Reflection.PropertyInfo =
  Boolean CapsLock {Name = "CapsLock";
                    CanRead = true;
                    CanWrite = false;
                    DeclaringType = System.Console;
                    PropertyType = System.Boolean; ...}
{% endhighlight %}

Однако функцией будет сложно воспользоваться, если надо будет получить `PropertyInfo` уровня экземпляра, не имея самого экземпляра класса. Чтобы решить данную проблему, можно позволить помимо выражения доступа к свойству, передавать лямбда-выражение, состоящие из выражения доступа к свойству через параметр лямбды:

{% highlight fsharp %}
<@ fun(s: string) -> s.Length @>

val it : Quotations.Expr<(string -> int)> =
  Lambda (s, PropertyGet (Some (s), Int32 Length, []))
{% endhighlight %}

Новая версия функции `propertyof` принимает вид:

{% highlight fsharp %}
let propertyof expr =
  match expr with
    | PropertyGet(_, info, _) -> info
    | Lambda(arg, PropertyGet(Some(Var var), info, _))
        when arg = var -> info
    | _ -> failwith "Not a property expression"
{% endhighlight %}

Тут и раскрывается вся соль совпадения с образцом: шаблоны-образцы могут быть *вложены друг в друга*, что делает pattern-matching очень мощной техникой, позволяющей легко «опознавать» сложные структуры и конструкции различных объектов. То есть если выражение `expr` является лямбда-выражением, то параметру лямбда выражение будет дано имя `arg`, а тело лямбда-выражения будет проверяться на соответствие шаблону `PropertyGet(Some(Var var), info, _)`, который совпадает с выражениями доступа к свойству уровня экземпляра (иначе первый параметр шаблона `PropertyGet` будет равняться `None`). Причём экземпляр, к чьему свойству происходит обращение, должен быть задан переменной, совпадающей с шаблоном `Var var`. Осталось лишь проверить с помощью *guard-выражения* `when` идентичность переменной `var` и аргумента лямбда-выражения `arg`, тем самым запретив к совпадению лямдба-выражения вида: `fun x -> someOtherVar.Property`. Вот и всё!

Ок, давайте попробуем ещё один вариант выражения, доступа к свойству необычного литерала (`123I` – это числовой литерал типа `BigInteger` в F#):

{% highlight fsharp %}
propertyof<@ 123I.IsZero @>

System.Exception: Not a property expression
   at FSI_0045.propertyof(FSharpExpr expr)
   at <StartupCode$FSI_0049>.$FSI_0049.main@()
{% endhighlight %}

Хм, как же на самом деле цитируется данное выражение?

{% highlight fsharp %}
<@ 123I.IsOne @>

val it : Quotations.Expr<bool> =
  Let (copyOfStruct,
     Call (None, BigInteger FromInt32[BigInteger](Int32), [Value 123]),
     PropertyGet (Some copyOfStruct, Boolean IsOne, []))
{% endhighlight %}

То есть на самом деле F# создаёт `let`-биндинг, инициализирует его конструктором `BigInteger` и затем осуществляет обращение к свойству данного биндинга, то есть выражение `123I.IsOne` цитируется как `let copyOfStruct = 123I in copyOfStruct.IsOne`. Добавим образец, совпадающий и с такими выражениями, функция примет вид:

{% highlight fsharp %}
let propertyof expr =
  match expr with
    | PropertyGet(_, info, _) -> info
    | Lambda(arg, PropertyGet(Some(Var var), info, _))
    | Let(arg, _, PropertyGet(Some(Var var), info, _))
        when arg = var -> info
    | _ -> failwith "Not a property expression"
{% endhighlight %}

Обратите внимание, что я объединил два образца через *ИЛИ-шаблон* `|` (ещё пример: `match x with 1 | 2 | 3 -> true | _ -> false`), так как оба образца содержат одинаковый набор имён для совпадений (`arg`, `var`, `info`) соответственно идентичных типов. Обратите внимание, что ограничивающее `when`-выражение тут действует на оба возможных совпадения *ИЛИ-шаблона*. Проверяем работоспособность:

{% highlight fsharp %}
[ propertyof<@ System.Console.Out @>
  propertyof<@ (null: Type).IsClass @>
  propertyof<@ "someStringLiteral".Length @>
  propertyof<@ fun(x: string) -> x.Length @> ]

|> List.iter (printfn "%A")
{% endhighlight %}

Выводит на экран:

    System.IO.TextWriter Out
    Boolean IsClass
    Int32 Length
    Int32 Length

Ок, остановимся на данном варианте и в следующем посте попробуем описать функцию посложнее: `methodof`.