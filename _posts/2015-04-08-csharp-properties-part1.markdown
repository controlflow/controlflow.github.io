---
layout: post
title: "Дизайн и эволюция свойств в C# (часть 1)"
date: 2015-04-08 17:52:00
author: Шведов Александр
tags: csharp properties design
---

Идея поста родилась из обычной рабочей задачи — поддержать нововведения языка C# 6.0 в ReSharper. Как обычно, все задачи в ReSharper оказываются в 5-10 раз сложнее, чем кажется на первый взгляд. Особой головной болью оказалась поддержка новых возможностей свойств в C# 6.0, так как изменения языка затрагивали массу кода имеющейся функциональности (далеко не всегда очевидным образом). Переделки заняли несколько месяцев, иногда вынуждая переписывать некоторые рефакторинги практически целиком (конкретно —  "Convert property to auto-property"), что заставило меня задуматься — почему все *настолько сложно* в мире свойств C#? Как так получилось, что работая со свойствами C# в IDE-инструментарием, надо постоянно держать в голове просто массу знаний о них? Чувствуют ли эту "сложность" обычные программисты?

Итак, сегодня я предлагаю вам в деталях обсудить понятие "свойства" на примере языка C# с самой первой его версии, немного поразмышлять о дизайне языков программирования, о том куда этот дизайн может катится и о том, можно ли хоть что-нибудь исправить.

## Ликбез по свойствам

### Что это вообще такое?

Давайте вернемся во времена C# 1.0 и рассмотрим определение канонического DTO-класса, инкапсулирующего некоторые данные. В отличие от Java, объявления класса в C# могла содержать не только поля/методы/классы, но и еще одну разновидность членов класса — объявления свойств:

```c#
class Person {
  private string _name;

  public Person(string name) {
    _name = name;
  }

  // property declaration:
  public string Name {
    get { return _name; }
    set { _name = value; }
  }
}

// property usage:
Person person = new Person();
person.Name = "Alex";
Console.WriteLine(person.Name);
person.Name += " the cat";
```

Свойства представляю собой члены класса, обладающие именем и типом, а так же содержащие в себе объявления "аксессоров". Акцессоры немного похожи на объявления методов, за исключением, например, явной указания типа возвращаемого значения и списка формальных параметров. Существуют два вида аксессоров свойств — getter'ы и setter'ы, вызываемых при обращении к свойству на чтение и запись соответственно. Возможно, на тот момент это казалось языковым средством неземной красоты, по сравнению со шляпой из пары методов в Java (которую шлепают до сих пор, в 2015 году):

```java
class Person {
  private String _name;

  public String getName() {
    return _name;
  }

  public void setName(String value) {
    _value = value;
  }
}

Person person = new Person();
person.setName("Alex");
Console.WriteLine(person.getName());
person.setName(person.getName() + " the cat");
```

### Мотивация

ОК, зачем нам вообще нужны свойства? Дело в том, что в высокоуровневых языках, таких как в Java и C#, поля классов представляют собой достаточно низкоуровневые конструкции<sup>1</sup>. Доступ к полю просто считывает или записывает область памяти некоторого известного размера по некоторому смещению, статически известному среде исполнения. Из такой низкоуровневости полей следует, что:

* Между разными полями и полями разных типов не существует унифицированного "интерфейса" (такого, например, как указатель на исполняемый код), что не позволяет организовать к ним полиморфный доступ (написать код, абстрагированный от знания о конкретном типе, к полю которого он обращается);

* Не существует возможности перехвата обращений к полю для исполнения дополнительных проверок консистентности, инварианта класса. На практике это же означает невозможность отладить программу, перехватив обращения к полям на чтение/запись через точку прерывания.

Помимо этого, практика показывает, что в классах часто удобно выставлять наружу какие-либо данные, не имея их в своем состоянии — то есть вычислять данные по какому-нибудь правилу при каждом обращении, забирать у какого-нибудь внутреннего объекта и т.п.

Все эти проблемы можно было успешно решить существующими в языке средствами — введя пару методов для доступа к значению поля, реализуя ими члены интерфейса или исполняя произвольный код проверок до или после записи:

```c#
interface INamedPerson {
  string GetName();
  SetName(string value);
  int GetYear();
}

class Person : INamedPerson {
  private string _name;

  public string GetName() { return _name; }

  public void SetName(string value) {
    if (value == null) throw new ArgumentNullException("value");
    _value = value;
  }

  public int GetYear() {
    return DateTime.Now.Year;
  }
}
```

Чем неудобно такое решение?

* Мы потеряли привычный синтаксис доступа к данным в полях:

```c#
foo.Value += 42;
// vs
foo.SetValue(foo.GetValue() + 42);
```

* В программе на самом деле никак не выражено, что все три сущности — поле и пара методов — имеют какую-либо *связь*. Методы и поля могут иметь разный уровень видимости, разное имя, разную "статичность" и "виртуальность".

* Чтобы намекнуть на общую связь, мы объявили три сущности имеющими подстроку "name" в именах. При рефакторинге нам придется обновить все три имени. Аналогично с упоминанием типа данных. Подобное соглашение об именовании упрощает жизнь в Java, но носит лишь рекомендательный характер (компилятор не будет бить по рукам в случае игнорирования соглашений).

### Решение с помощью свойств

Давайте посмотрим на пример кода выше, переписанный с использованием объявлений свойств C#:

```c#
interface INamedPerson {
  string Name { get; set; }
  int Year { get; }
}

class Person : INamedPerson {
  private string _name;

  public string Name {
    get { return _name; }
    set {
      if (value == null) throw new ArgumentNullException("value");
      _name = value;
    }
  }

  public int Year {
    get { return DateTime.Now.Year; }
  }
}
```

Кода по-прежнему невыносимо много, но определенные удобства свойства все же привносят:

* Тела аксессоров синтаксически объединены в один блок, а значит логически разделяют один и тот же уровень видимости, модификаторы статичности и виртуальности;

* Подстрока "name" теперь встречается в объявлениях "всего" два раза, так же как и тип `String`. Параметр `value` объявляется в `set`-аксессоре неявным образом, что тоже экономит немного кода;

* Синтаксис доступа к свойствам аналогичен привычному и простому синтаксису доступа к полю, что еще и значительно облегчает инкапсуляцию поля в свойство вручную (без автоматизированных рефакторингов кода);

* За свойством может и вовсе не стоять поля с состоянием, тела аксессоров могут содержать произвольный код;

* Не смотря на то, что аксессоры все равно компилируются в тела методов `string get_Name()` и `set_Name(string value)`, в метаданных хранится специальная запись о свойстве, как о единой сущности (аналогично для событий C#). Таким образом понятие "свойства" существует для среды исполнения, это не только сущность компилятора C#. Как следствие, например, свойства можно помечать атрибутами CLI как единую сущность, что имеет множество применений на практике.

Как я не пытался структурировать дальнейшие рассуждения, дальше получились просто перечислить приемущества и недостатки свойств вообще и дизайна свойств конкретно в языке C# самой первой версии.

### Set-only свойства

Тут нечего особо обсуждать — в C# никогда не должно было случиться свойств из единственного `set`-аксессора:

```c#
class Foo {
  public int Property {
    set { SendToDeepSpace(value); }
  }
}
```

Дизайн языка программирования можно сравнить с многомерной задачей оптимизации. Найдя локальный максимум функции от многих переменных (гибкость, функциональность, каноничность, синтаксическая красота и многое другое) может казаться, что выбранный дизайн достаточно канонический. Однако, всегда есть вероятность, что пожертвовав максимумом по некоторому измерению, можно прийти в более разумный максимум по всем измерениям.

Например, запрет объявления свойств из одного `set`-аксессора может казаться натуральной "заплаткой" с точки зрения красоты спецификации языка, каким-то искусственным ограничением, разрушающим симметрию между разными типами аксессорами<sup>2</sup> (`get`-аксессоры становятся обязательными).

С другой стороны, если не запрещать такие очевидно странные сущности (на такие `set`-only свойства в языке похожи только `out`-параметры, но их становится возможно считывать после первого присвоения), то начинает случаться реальный говнокод с `set`-only свойствами (я пару раз встречал). Если пару раз наткнуться на такие свойства, не понимая почему их значение не видно в отладчике, то начинаешь ценить совсем не каноничность определения свойства в спецификации, а в количество ~~фашизма~~запретов в компиляторе.

### Разновидности доступа

Простой императивный язык программирования — это такой, в коде которого можно увидеть использование (не объявление!) переменной `foo` и всегда знать, что это либо чтение переменной, либо запись. Но когда-то очень давно случился язык программирования C и теперь у нас есть вот эти мутанты:

```c#
variable ++;
variable += 42;
```

То есть появляется новая *разновидность* использования — чтение/запись<sup>3</sup>. Так как C# стремится синтаксически устранить различия использования свойств от использования полей, то подобные операторы разрешены и для свойств (доступных для записи), компилируясь в вызовы `get` и `set`-аксессоров:

```c#
++ person.Age;
// is
person.set_Age(person.get_Age() + 1);
```

Казалось бы: замечательно, что это работает — ведь на то и нужен язык высокого уровня, что скрывать низкоуровневые детали реализации свойств как вызовов методов. Проблема в том, что в C# есть еще один источник использований на чтение и запись одновременно — `ref`-параметры:

```c#
void M(ref int x) { x += 42; }

int x = 0;
M(ref x); // read-write usage
```

К сожалению, `ref`/`out`-параметры в C# — не менее низкоуровневые конструкции, чем поля типов. Для среды исполнения `ref`/`out`-параметры имеют специальный управляемый ссылочный тип, отличающегося от обычных unmanaged-указателей только запретом на арифметический операции и осведомленностью GC об объектах по таким указателям (передача поля класса/элемента массива как `ref`/`out`-параметра удерживает весь объект/массив от сборки мусора).

Из-за невозможности превратить два метода аксессоров свойства в один указатель на изменяемую область памяти, компилятор C# банально не позволяет передавать свойства в `ref`/`out`-параметры. Это редко нужно на практике, но выглядит как "спонтанное нарушение симметрии" в языке. Интересно, что другой .NET-язык — Visual Basic .NET — без особых проблем скрывает для пользователя разницу между свойствами и полями:

```vbnet
sub F(byref x as integer)
  x += 1
end sub

interface ISomeType
  property Prop as integer
end interface

dim i as ISomeType = ...
F(i.Prop) ' OK
```

Грубо говоря, VB.NET разрешает передавать в `byref`-параметры вообще любые выражения, автоматически создавая временную локальную переменную (и передавая ее адрес). Если в качестве аргумента `byref`-передано изменяемое свойство, то VB.NET автоматически присвоит свойству значение временной переменной, но только по окончанию вызова. Есть вероятность (крайне маленькая), что метод с `byref`-параметром каким-нибудь магическим образом должен зависеть от актуального значения переданного в него свойства и тогда удобность превратится в грабли.

Но граблей и без этого хватает: например, если взять в скобки `i.Prop` из примера выше, то присвоение свойству перестанет происходить (в качестве `byref`-аргумента начнет передаваться временное значение выражения в скобках, а не само *свойство-как-адрес*). Помимо этого, присвоение свойству не случится если после присвоения `byref`-параметра в методе возникнет исключение. Вот и не понятно становится — стоят-ли эти грабли в языке потерянной универсальности?




[Продолжение следует...]({% post_url 2015-04-08-csharp-properties-part2 %})



<sup>1</sup> В CLR чтение полей `MarshalByReference` объектов на самом деле всегда виртуальное (до тех пор пока его не передать в `ref`/`out`-параметр).

<sup>2</sup> В C# уже существуют другие типы членов класса с аксессорами — *события* — для которых компилятор всегда требует определить оба ацессора (`add` и `remove`).

<sup>3</sup> На самом деле я конечно не упоминаю другие типы использований сущностей в C# — использования в XML-документации, использования имен сущностей в операторе `nameof()` из C# 6.0, "частичные" использования на чтение и запись при работе с типами-значениями:

```c#
   Point point;

   point.X = 42;            var x = point.X;
// |     |__ write                  |     |__ read
// |________ partial write          |________ partial read
```