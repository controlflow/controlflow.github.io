---
layout: post
title: "С# attribute-target-specifier"
date: 2010-11-04 18:51:04
categories: 1480019169
tags: csharp attributes typevar
---
Забавно, не смотря на то, что грамматика C# для указания аннотируемого атрибутом элемента языка, предусматривает ограниченный набор значений:

> *attribute-section:*<br/>
>     [ *attribute-target-specifier<sub>opt</sub>  attribute-list* ]<br/>
>     [ *attribute-target-specifier<sub>opt</sub>  attribute-list ,* ]<br/>
> <br/>
> *attribute-target-specifier:*<br/>
>     *attribute-target :*<br/>
> <br/>
> *attribute-target:*<br/>
>     `field`<br/>
>     `event`<br/>
>     `method`<br/>
>     `param`<br/>
>     `property`<br/>
>     `return`<br/>
>     `type`

На деле (компилятор С# 4.0) всё оказывается несколько иначе, код:

```c#
[someCrazyAttributeTargetLocation: Serializable]
class Foo { }
```

Компилируется без ошибок, но с одним warning’ом:

> warning CS0658: ‘someCrazyAttributeTargetLocation’ is not a recognized attribute location. All attributes in this block will be ignored.

Соответственно, в рантайме получаем `typeof(Foo).IsSerializable == false`. Однако, [читая](http://rsdn.ru/forum/dotnet/4024505.aspx) Владимира Решетникова на rsdn, можно обнаружить, что существует ещё один *attribute-target-specifier*, не перечисленный в грамматике C#, который компилятор воспринимает без warning’а:

```c#
[AttributeUsage(AttributeTargets.GenericParameter)]
sealed class FooAttribute : Attribute { }

sealed class Bar<[typevar: Foo] T> { }

```

Знакомьтесь, скрытый *attribute-target-specifier* - `typevar`. Применение атрибута где-либо вне типа-параметра (если убрать `[AttributeUsage]`) будет результировать предупреждением *CS0658*.

Компилятор F# более строг и использование произвольных *attribute-target* не позволяет вовсе.