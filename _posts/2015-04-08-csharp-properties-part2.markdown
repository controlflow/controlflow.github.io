---
layout: post
title: "Дизайн и эволюция свойств в C# (часть 2)"
date: 2015-04-08 17:53:00
author: Шведов Александр
tags: csharp properties design
---

Продолжаем обсуждать проблемы и последствия дизайна свойств в языке программирования C# 1.0.

### Пересечение с типами-значениями

Существование типов-значений в языке очень усложняет практически все, что можно представить. Изменяемые типы-значения увеличивают сложность еще на порядок. Одна из причин усложнения языка - введение понятия адреса значения или lvalue (грубо говоря, выражения которое пишется слева от оператора присвоения).

Одна из причин успеха языка программирования Java как раз в простоте языка из-за отсутствия ссылочных и указательных типов, программисту не приходится на практике сталкиваться с понятиями "lvalue" и "rvalue" из мира C/C++. В Java достаточно запомнить, что "адрес" ожидается только слева от знака присвоения и в качестве операнда мутирующих операторов типа `+=` и `++`. Во всех остальных местах языка оперируют только значениями (включая ссылки-на-объекты-как-значения).

На первый взгляд, в C# помимо таких же присвоений и изменяющих значение операторов, адрес ожидается в качестве аргументов `out`-параметров, что не сильно усложняет картину. Однако, из-за того, что методы и другие члены уровня экземпляра, определенные на структурах, могут изменять эти самые структуры, во все такие члены структур в качестве `this` всегда передается адрес значения (как неявный `ref`-параметр, изменяемый!). То есть даже очень простой код вида `var d = dateTime.AddDays(1);` на самом деле использует переменную `dateTime` как адрес, а не значение, что совершенно незаметно.

На такие случаи спецификация C# вводит понятие выражений, *классифицированных-как-переменная* (*classified as a variable*), чем-то похожее на понятие "lvalue". Однако с этим понятием сопряжено множество нюансов. Например, временные значения (типа возвращаемого значения вызова метода или обращения к свойству на чтение) и чтения `readonly`-полей (вне конструктора) *реклассифицируются* как переменные, чтобы на них все равно можно было вызывать члены структур (вызовы происходят на копии оригинального значения). Со всеми этими нюансами можно разобраться покурив поведение этого кода под отладчиком:

```c#
struct Box {
  public int Value;
  public void Inc() { Value++; }
}

class Foo {
  Box _f;
  readonly Box _r;

  Box _p;
  Box P {
    get { return _p; }
    set { _p = value; } // never actually used
  }

  public Foo() {
    _f.Inc(); // mutates '_f' field, classified as a variable
    _r.Inc(); // mutates '_r' readonly field, classified as a variable
    P.Inc(); // mutates temp value of 'P', reclassified as a variable

    System.Action f = () => {
      _r.Inc(); // mutates temp copy of '_r', reclassified as a variable
    };
  }

  public void InstanceMethod() {
    _f.Inc(); // mutates '_f' field, classified as a variable
    _r.Inc(); // mutates temp copy of '_r', reclassified as a variable
    P.Inc(); // mutates temp value of 'P', reclassified as a variable
  }
}
```

Таким образом свойства ведут себя наиболее простым способом, никогда не играя роль адреса значения. В итоге мы имеем в языке три немного отличающихся поведения для изменяемых полей, `readonly`-полей и свойств. При этом компилятор C# старается защитить нас от очевидных глупостей, запрещая на членах не классифицируемых как переменные (`readonly`-полях и свойствах) с типом типа-значения вызывать конструкции, явно нацеленные на модификацию значения:

```c#
interface IBar {
  Box Box { get; set; }
}

void M(IBar bar) {
  bar.Box.Value ++; // CS1612: Cannot modify the return value of 'IBar.Box'
                    // because it is not a variable
  bar.Box.Value = 42; // CS1612 too
  bar.Box.Inc(); // ok! modifies temp 'Box' value
}
```

Но C# ничего не знает о поведении методов структур (изменяют-ли они значение), поэтому вынужден всегда разрешать их вызовы. На самом деле, C# мог бы попытаться устранить различия в поведении между изменяемыми полями и `get`/`set`-свойствами - в примере выше для того чтобы заставить `bar.Boo.Value++;` работать надо лишь вызвать `set`-аксессор `bar.Boo` и передать измененное выражением `.Value++` значение типа `Box` обратно в `bar`. Но с другой стороны, кажется, что в среднем по больнице разработчики никак не будут ожидать от выражения `bar.Box.Value++;` вызова `set`-аксессора свойства `bar.Box`, ведь все выражение выглядит как доступ на чтение и только `.Value` подвергается модификации.

Стоит заметить, что всех описанных выше проблем и разницы в поведении можно легко избежать, если делать структуры C# неизменяемыми - тогда становится совершенно все равно, на копии значения или адресе что-то вызвали, все работало бы одинаково.

### Типизация задержки

Одно из самых замечательных последствий существования свойств в C# — это "типизация" задержки. Под "задержкой" я подразумеваю среднее время возвращения исполнения после обращения к некоторому коду. Понятия "задержки" и связанное понятие "эффективности" (очень советую посмотреть [видео с Эриком Мейджером на эту тему](http://channel9.msdn.com/Blogs/Charles/Erik-Meijer-Latency-Native-Relativity-and-Energy-Efficient-Programming)) — практически точно такие же метрики программ, как "O большое" по времени или памяти.

Типизация занимается *классификацией* значений и других сущностей программы. Метрики вида "эта функция вычисляется за *O(n)*" или "эта функция пользуется константным количеством памяти" — вполне могут выступать в роли *типов* и их точно так же можно проверять на корректность (например, запретить вызывать функции, класифицированных как *O(n<sup>2</sup>)*, из *O(n)*-функций). Спроса на такую разновидность типизации я не наблюдал, так же как и языков программирования, способных выразить и валидировать подобные аспекты программ.

С другой стороны, в реальной жизни мы на самом деле часто сталкиваемся с попытками классифицирования понятия задержки того или иного метода некоторого API. Самый распространенный пример — Promise-объекты. Например, в WinRT (новом провальном системном API приложений для Windows 8) все методы, которые могут исполняться достаточно долго, сделаны только возвращающими значения типов `Task` или `Task<T>`. Все их использования вынуждают пользователя породить асинхронность и быть готовым к задержке (не забивать UI-поток в ожидании окончания тяжелых операций), потому что из `Task<T>` нет легкого способа вытащить значение `T` (за `.Value` или `.Wait()` можно сразу убивать). То есть сущности программы разделяются хотя бы на два класса — пригодные для синхронных вызовов и пригодных только для работы в асинхронном коде.

Свойства в C# — тоже, в некотором роде, типизируют задержку исполняемого кода. От свойства обычно никак не не ожидают, что при доступе оно полезет на диск или в сеть. Это правило конечно же неформальное, никто это не проверяет, существуют известные отклонения (например, свойство `Lazy<T>.Value`), но все же на практике API из методов и свойств позволяет иметь некоторые ожидания от того или иного члена класса в плане "задержки".

### Типизация функциональной чистоты

Другой не менее важный аспект свойств — опять же неформально, но большинством C# разработчиков ожидается, что доступ к свойству на чтение функционально чист. Формальное определение чистоты достаточно сложно дать применительно к C#/.NET, поэтому я буду оперировать какой-нибудь абстрактной чистотой. Здравый смысл позволяет ожидать, что доступ к свойству на чтение не может изменить видимое клиенту состояние класса (то есть вычислить что-то и закэшировать в приватном изменяемом поле — ОК, вполне себе чисто), не делает I/O или запроса к СУБД.

Чистота свойств настолько натуральна и ожидаема, что отладчик VisualStudio не брезгает вызывать любые свойства в окнах отладчика типа Watch — это очень удобно и в 99.99% случаев не имеет никакого эффекта на исполнение программы под отладчиком. Помимо отладчика, IDE-тулингу типа ReSharper для автоматических рефакторингов кода иногда крайне полезно уметь спросить любое выражение языка "а чистый-ли ты, дружок?" — например, чтобы переупорядочить код изменяя порядок вычисления, но сохраняя семантику исходной программы. Конкретно в ReSharper некоторые рефакторинги полагаются на чистоту доступа к свойству (даже не смотря на очевидные отклонения как `System.DateTime.Now`) и жалоб на сломанную семантику программы (после применения рефакторинга) практически никогда не поступало.

```c#
if (foo.Bar != null) foo.Bar.Baz();
```

Код выше *очень распространен* в C#, из-за этого в движке dataflow-анализов ReSharper когда-то давно пришлось поддерживать не только локальные переменные, но еще и собирать знания о значениях полей и свойств, к которым достучались из локальных переменных (как `foo.Bar` из примера выше). При этом такой анализ не является sound (результаты не всегда корректны), он не учитывает потенциальный aliasing ссылок на объекты, панически инвалидирует знания о свойствах/полях при вызовах методов на той или иной переменной (вызовы типа `foo.M()` инвалидируют знания о членах типа `foo.Bar`). Но что поделаешь, если такой код пишут регулярно, отдача от анализа должна быть практически мгновенной и >95% свойств действительно являются чистыми функциями при чтении?

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




[Продолжение следует...]({% post_url 2015-04-08-csharp-properties-part3 %})



