---
layout: post
title: "Design and evolution of properties in C# (part 2)"
date: 2015-04-08 17:53:00
author: Aleksandr Shvedov
tags: csharp properties design
---

Continuing the discussion on the issues and consequences of property design in the C# 1.0 programming language.

### Intersection with Value Types

The existence of value types in the language significantly complicates almost everything else. Mutable value types increase the complexity even further. One of the reasons for this extra complexity in the language is the introduction of the concept of the values with an address or "lvalue" (roughly speaking, an expression that appears on the left side of the assignment operator).

One reason for the success of the Java programming language lies in its simplicity due to the absence of reference and pointer types. In Java, the programmer doesn't have to deal with the concepts of "lvalue" and "rvalue" from C/C++. In Java, it is enough to remember that an "address" is only expected on the left side of the assignment operator and as an operand for mutating operators like `+=` and `++`. In all other parts of the language, only values are operated on (including references to objects treated as values).

At first glance, in C#, besides such assignments and mutating operators, the address is expected as arguments to `out` parameters, which doesn't complicate the picture too much. However, due to the fact that methods and other instance-level members defined on structs can modify these structs, the address of the value is always passed as `this` to all such struct members (as an implicit `ref` parameter, which is mutable!). This means that even very simple code like `var d = dateTime.AddDays(1);` actually uses the `dateTime` variable as an address, not as a value, which is invisible for user.

For such cases, the C# specification introduces the concept of *expressions classified as variables*, which is somewhat similar to the concept of "lvalue." However, this concept comes with many nuances. For example, temporary values (such as the return value of a method call or reading a property) and reading `readonly` fields (outside of the constructor) are *reclassified* as variables so that struct members can still be called on them (calls happen on a copy of the original value). These nuances can be explored by examining the behavior of this code under a debugger:

```c#
struct Box
{
  public int Value;
  public void Inc() { Value++; }
}

class Foo
{
  Box _f;
  readonly Box _r;

  Box _p;
  Box P
  {
    get { return _p; }
    set { _p = value; } // never actually used
  }

  public Foo()
  {
    _f.Inc(); // mutates '_f' field, classified as a variable
    _r.Inc(); // mutates '_r' readonly field, classified as a variable
    P.Inc(); // mutates temp value of 'P', reclassified as a variable

    System.Action f = () =>
    {
      _r.Inc(); // mutates temp copy of '_r', reclassified as a variable
    };
  }

  public void InstanceMethod()
  {
    _f.Inc(); // mutates '_f' field, classified as a variable
    _r.Inc(); // mutates temp copy of '_r', reclassified as a variable
    P.Inc(); // mutates temp value of 'P', reclassified as a variable
  }
}
```

Thus, properties behave in the simplest way, never acting as an address of a value. As a result, the language has three slightly different behaviors for mutable fields, `readonly` fields, and properties. At the same time, the C# compiler tries to protect us from obvious mistakes by disallowing operations on members that are not classified as variables (e.g., `readonly` fields and properties) with value-type fields in a way that explicitly targets modifying the value:

```c#
struct Box
{
  public int Value;
}

interface IBar
{
  Box Box { get; set; }
}

void M(IBar bar)
{
  // CS1612: Cannot modify the return value of 'IBar.Box'
  //         because it is not a variable
  bar.Box.Value++;

  bar.Box.Value = 42; // CS1612 too

  bar.Box.Inc(); // OK, but modifies temp 'Box' value
}
```

However, C# doesn't know about the behavior of struct methods (whether they modify the value or not)<sup>1</sup>, so it is forced to always allow their calls. In fact, C# could try to eliminate the differences in behavior between mutable fields and `get`/`set` properties. In the example above, in order to make `bar.Box.Value++;` work, one would only need to call the `set` accessor for `bar.Box` and pass the modified value (from the `.Value++` expression) of type `Box` back to `bar`. But on the other hand, it seems that developers generally wouldn't expect the `set` accessor of `bar.Box` to be called from an expression like `bar.Box.Value++`, since the whole expression looks like a read-access operation, with only `.Value` being modified.

It is worth noting that all the described problems and differences in behavior can be easily avoided if C# structs are made immutable — then it wouldn't matter whether something is called on a copy of the value or an address, as everything would work the same.

### Classification of latency

One of the most remarkable consequences of the existence of properties in C# is the classification of latency. By "latency," I mean the average time it takes for execution to return after calling a certain piece of code. The concepts of "latency" and the related concept of "efficiency" (I highly recommend watching [this video with Erik Meijer on the subject](http://channel9.msdn.com/Blogs/Charles/Erik-Meijer-Latency-Native-Relativity-and-Energy-Efficient-Programming)) are nearly the same metrics for programs as "big-O" for time or memory.

Typing is concerned with the *classification* of values and other entities in a program. Metrics like "this function runs in *O(n)*" or "this function uses a constant amount of memory" can easily serve as *types*, and they can be checked for correctness in the same way (for example, prohibiting the calling of functions classified as *O(n<sup>2</sup>)* from within *O(n)* functions). I have not seen a demand for this kind of typing, nor have I come across programming languages that can express and validate such aspects of programs.

On the other hand, in real life, we often encounter attempts to classify the concept of latency for a particular method in some API. The most common example is Promise objects. For instance, in WinRT (the new, failed system API for Windows 8 applications), all methods that can take a long time to execute return values of type `Task` or `Task<T>`. Using them forces the developer to handle asynchrony and be prepared for latency (not blocking the UI thread while waiting for heavy operations to complete), because extracting the value `T` from a `Task<T>` is not straightforward (using `.Value` or `.Wait()` can immediately cause problems). So, the program's entities are divided into at least two classes — those that are suitable for synchronous calls and those that are only suitable for asynchronous code.

Properties in C# also, in a sense, classify the latency of the code. Typically, no one expects that accessing a property will involve disk or network operations. This rule is informal, of course, no one enforces it, and there are known exceptions (such as the `Lazy<T>.Value` property), but in practice, the API consisting of methods and properties allows certain expectations regarding the "latency" of a class member.

### Classification of purity

Another equally important aspect of properties is that, again informally, most C# developers expect that reading a property should be functionally pure. Formally defining purity in the context of C#/.NET is quite difficult, so I will rely on an abstract concept of purity. Common sense suggests that reading a property should not modify the visible client state of the class (i.e., it’s fine to compute something and cache it in a private mutable field—this is still pure), nor should it perform I/O or query a database.

The purity of properties is so natural and expected that the Visual Studio debugger doesn't hesitate to call any property in debugging windows like Watch—this is very convenient, and in 99.99% of cases, it doesn't affect the program's execution while debugging. Apart from the debugger, IDE tooling like ReSharper for automated code refactorings can be extremely useful for checking whether an expression is "pure," for example, to reorder code while maintaining the program's original semantics. Specifically, in ReSharper, some refactorings rely on the purity of property access (even considering obvious exceptions like `System.DateTime.Now`), and complaints about broken semantics after applying the refactorings rarely arise.

```c#
if (foo.Bar != null)
{
  foo.Bar.Baz();
}
```

The code above is *very common* in C#, which is why, in the dataflow analysis engine of ReSharper, it was once necessary to support not only local variables but also gather knowledge about the values of fields and properties accessed from local variables (like `foo.Bar` in the example above). However, such analysis is not sound (the results are not always correct), as it does not account for potential aliasing of object references, and not very precise — it invalidates knowledge of properties/fields when methods are called on variables (calls like `foo.M()` invalidate knowledge of the members of `foo.Bar`). But what can you do when this code is written regularly, and the feedback from the analysis needs to be nearly instantaneous, with >95% of properties actually being pure functions when read?

### Модификаторы свойств и полиморфизм

Объединяя свойства в одну логическую сущность, в C# мы потеряли возможность управлять виртуальностью каждого аксессора свойства отдельно. Например, нельзя сделать виртуальным только `get`-аксессор. На первый взгляд может показаться, что это и к лучшему - такие модификаторы как `new` (сокрытие базовых членов класса по имени) разумно иметь только для свойства как единого целого. С другой стороны, начиная с C# 1.0 в языке образовались грабли, на которые я пару раз наступал:

```c#
abstract class B {
  public abstract int Value { get; }
}

class C : B {
  int _value;
    
  public override int Value {
    get { return _value; }
    set { _value = value; } // CS0546
  }
}
```

Так как модификатор `override` тоже распространяется на оба аксессора, а `set`-аксессору перекрывать в базовом классе нечего, то мы получаем ошибку компиляции:

> Error CS0546: 'C.Value.set': cannot override because 'B.Value' does not have an overridable set accessor

Скажу сразу, что в самой последней версии C# до сих пор вообще не существует способа добавить аксессор в переопределении полиморфного свойства. Большая-ли это проблема - не понятно, кажется что не особо и проблема. Является-ли необходимость добавить аксессор к полиморфному свойству нормальной практикой - тоже не понятно, больше похоже на code smell.

### Полиморфные аксессоры

Мне всегда казалось, что посмотрев на объявление свойства в C# можно однозначно сказать - доступно-ли оно для чтения или записи, просто по списку аксессоров свойства. Взглянув на реализации `IProperty.IsWriteable`/`IProperty.IsReadable` внутри моделей ReSharper, я был неприятно удивлен - все три свойства из объявлений классов ниже можно читать и записывать, не смотря на *синтаксический вид* их объявленя:

```c#
abstract class B {
  public abstract int Value { get; set; }
}

abstract class C : B {
  public override int Value { set { /* ... */ } }
}

class D : C {
  public override int Value { get { return 42; } }
}
```

Если объявление свойства не имеет необходимого объявления аксессора, но имеет модификатор `override`, то чтобы ответить на вопрос "записываемости"/"читаемости"" свойства, необходимо перейти к *семантической* модели, обойти иерархию базовых классов и проанализировать наличие в переопределенных свойствах необходимого аксессора.

Дело в том, что переопределение (`override`) свойства не определяет новое свойство, а лишь *специализирует* тела аксессоров. Переопределение свойств выглядит уже достаточно запутанной частью языка чтобы делать ее слишком гибкой и запутывать язык еще больше. Я думаю, что следовало бы запретил переопределять аксессоры частично, даже если в большинстве случаев пользователям пришлось бы дописывать аксессор вида `get { return base.Value; }`. Сложно представить случаи, когда частичное переопределение аксессоров не было бы code smell'ом.

### Проблема выбора: свойство или поле

Как только язык предоставляет программисту возможность сделать одно и то же несколькими способами - программисты тут же начинают пользоваться этими всеми возможными способами, это закон! Что еще хуже - устраивать холивары на тему какой из способов лучше, писать разные гайдлайны (а потом еще и инструментарий!) и так далее.

Из этого следует сделать только один вывод - в дизайне языка программирования важно предоставить пользователю гибкость решать все мыслимые и немыслимые проблемы из его предметной области, но при этом ровно столько гибкости, чтобы та или иная проблема решалась/выражалась *единственным* способом.

С тех пор, как в C# существуют свойства (с начала времен), существуют и споры насчет того, должны ли публичные поля.

* TODO: private "ассоциируется" с полями
* TODO: фреймворки типа WPF требуют свойства
* TODO: поля почти всегда приватные

### Проблема выбора: инкапсулировать или нет

Из-за той же проблемы существования выбора, среди C#-программистов существует разногласие по-поводу того, как обращаться к инкапсулированным данным внутри объявления владеющего данными класса. Думаю, как минимум половина разработчиков (включая меня) напишет простой DTO-класс как-нибудь вот так:

```c#
class Person {
  string _name;

  public string Name {
    get { return _name; }
    set {
      if (value == null) throw new ArgumentNullException("value");
      _name = value;
    }
  }

  public Person(string name) {
    if (name == null) throw new ArgumentNullException("name");
    _name = name;
  }

  public void SayHello() {
    Console.WriteLine(_name);
  }
}
```

Лично я до сих пор не могу объяснить себе, почему обращаться к полю внутри класса мне нравится больше. Даже осознавая, что этот подход чреват проблемами/рефакторингом, если свойство вдруг необходимо будет сделать полиморфным (скорее всего все обращения к нему тоже должны будут стать полиморфными). Даже разница в производительности доступа к свойству и полю не играет роли, потому что инлайнер устраняет эту разницу.

Так или иначе, другая часть C#-разработчиков не видит причин обходить публичный интерфейс инкапусированных данных (не важно, есть там валидация как в примере выше или нет) и внутри объявления класса тоже пользуется только свойством:

```c#
class Person {
  ...

  public Person(string name) {
    Name = name;
  }

  public void SayHello() {
    Console.WriteLine(Name);
  }
}
```

Однако жизнь несправедлива и даже они не могут быть счастливы. Потому что когда-нибудь появится новый программист и сделает класс `Person` неизменяемым (поле `_name` станет `readonly`-полем). В этом случае инициализация просто вынуждена будет происходить через обращение к полю напрямую:

```c#
class Person {
  readonly string _name;
  readonly IPersonRepository _repository;

  public string Name { get { return _name; } }

  public Person(string name, IPersonRepository repository) {
    if (name == null) throw new ArgumentNullException("name");
    _name = name; // 1
    _repository = repository;
  }

  public void SayHello() {
    _repository.SendHelloMessage(Name); // 2
  }
}
```

Забегая вперед, хочется заметить, что второй подход (инкапсулировать доступ когда это возможно) выглядит более каноничным и чаще работающим как надо, а дальнейшее развитие языка позволило обойти необходимость в `readonly`-поле (для реализации тривиальных свойств только для чтения) и его инициализации из примера выше.

Однако, и у первого подхода есть свои замечательные стороны: невозможно игнорировать тот факт, что у классов очень часто есть поля, *вообще не нуждающиеся в инкасуляции* через свойства (как поле `_repository` из примера выше). И доступ к ним возможен *единственым* способом. Чаще всего стиль именование полей и свойств в C# отличается (`_field` и `Property`, например) и становится непонятно: почему доступ к инкапсулированным данным внутри объявления класса должен синтаксически отличаться? И причиной всему - одновременное существование и полей, и свойств...

### Ужасный синтаксис

* TODO: обилие скобок
* TODO: statement-тела




[To be continued...]({% post_url 2015-04-08-csharp-properties-part3 %})

<sup>1</sup> This was relaxed in future C# versions, by allowing `readonly` modifier on declaration of struct's instance members to indicate their immutability and to get rid of shallow copies.

