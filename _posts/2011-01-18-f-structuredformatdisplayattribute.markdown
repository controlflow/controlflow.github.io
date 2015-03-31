---
layout: post
title: "F# StructuredFormatDisplayAttribute"
date: 2011-01-18 21:10:00
categories: 2813440808
tags: fsharp printf sprintf StructuredFormatDisplayAttribute
---
Совсем маленький пост про совсем неизвестный атрибут `StructuredFormatDisplayAttribute` из состава стандартной бибилиотеки F#. Данный атрибут позволяет управлять логикой преобразования значений к текстовому виду согласно спецификатору формата `%A` (то есть при использовании функций `printf`, `sprintf` и других из модуля `Printf`) и отображению значений данного типа в интерактивной консоли F#. Обычно, определяя пользовательский тип:

{% highlight fsharp %}
type Person(name: string, age: int, money: decimal) =
     member __.Name  = name
     member __.Age   = age
     member __.Money = money

let alex = Person("Alex", 22, 200000m)
{% endhighlight %}

И создавая его экземпляры, вы будете видеть их в консоли F# interactive следующим образом:

```
val alex : Person = FSI.Person
```
Однако, переопределив метод `System.Object.ToString()`, можно наблюдать за внутренним состоянием объектов и в интерактивной консоли, так как F# interactive и `%A` используют переопределение `ToString()`, если таковое имеется:

{% highlight fsharp %}
type Person(name: string, age: int, money: decimal) =
     member __.Name  = name
     member __.Age   = age
     member __.Money = money
     override __.ToString() =
         sprintf "Person(%s, %d, %O)" name age money

let alex = Person("Alex", 22, 200000m)
{% endhighlight %}

Вывод:

```
val alex : Person = Person(Alex, 22, 200000M)
```
Тем не менее, тот текст, который возвращает `ToString()`, и который вы хотите наблюдать в консоли F# interactive или при выводе в формате `%A`, может отличаться. На этот случай и может понадобится атрибут `[<StructuredFormatDisplay>]`, которые позволяет задать формат вывода. Формат задаётся строкой вида `"Префикс {ИмяСвойства} Постфикс"`, где `Префикс` и `Постфикс` - любой необязательный текст, а `ИмяСвойства` - имя свойства, определённого в данном типе или его базовом классе:

{% highlight fsharp %}
[<StructuredFormatDisplay("Person (with Name='{Name}')")>]
type Person(name: string, age: int, money: decimal) =
     member __.Name  = name
     member __.Age   = age
     member __.Money = money
     override __.ToString() =
         sprintf "Person(%s, %d, %O)" name age money

let alex = Person("Alex", 22, 200000m)
{% endhighlight %}

Вывод принимает вид:

```
val alex : Person = Person (with Name='Alex')
```
Обратите внимание, что использовать можно имя только *одного* свойста, в строке формата нельзя использовать символы `{` и `}` (даже экранируя как `{{` и `}}`). Поддерживается доступ к свойствам, объявленным с модификатором доступа `private`.