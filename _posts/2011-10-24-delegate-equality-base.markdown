---
layout: post
title: "Delegate equality и квалификатор base."
date: 2011-10-24 14:14:00
author: Aleksandr Shvedov
tags: csharp clr .net delegate base
---
Как вы думаете, что выведет на экран этот код?

```c#
using System;
using System.Collections.Generic;
using System.Linq;

// класс с событием
class Boo {
  public event Action Event = delegate { };
  public void FireEvent() { Event(); }
}

// класс с виртуальным методом
class FooBase {
  public virtual void Bar() {
    Console.WriteLine("FooBase.Bar");
  }
}

// наследник, не переопределяющий Bar
class Foo : FooBase {
  public void Unsubscribe(Boo boo) {
    // отписка base.Bar от события Boo.Event
    Action f = () => boo.Event -= base.Bar;
    f();
  }

  public IEnumerable<int> OnceAgain(Boo boo) {
    // тоже отписка, только в итераторе
    boo.Event -= base.Bar;
    yield break;
  }
}

class Program {
  static void Main() {
    var foo = new Foo();
    var boo = new Boo();

    boo.Event += foo.Bar; // подписываемся

    foo.Unsubscribe(boo); // дважды отписываемся
    foo.OnceAgain(boo).ToList();

    boo.FireEvent(); // ?
  }
}

```

Логично предположить, что ничего не выведет, так как мы вроде как отписываемся от события тем же методом `FooBase.Bar`, которым изначально подписывались. Не смотря на то, что отписка происходит другим экземпляром делегата, она должна происходить корректно, так как у `System.Delegate` переопределены методы `GetHashCode`/`Equals`, проверяющие эквивалентность методов, на которые “указывают” делегаты (в нашем случае ещё и ссылочное равенство экземпляров, которым “принадлежит” экземплярный метод `Bar`).

Будучи скомпилированным компилятором C# версии до 4.0, код выше действительно ничего выводил, однако начиная с версии 4.0 компилятор генерирует такой код, что *отписки не происходит* (не в методе, ни в итераторе) и на экран выводится “`FooBase.Bar`”, что немного смущает, мягко говоря.

Всё дело тут, конечно же, в `base.`-вызове. Интересной его особенностью является то, что вызов базовой реализации виртуального метода происходит *не виртуально*. Это необходимо, так как в таблице виртуальных функций указателя на базовую реализацию той или иной виртуальной функции может уже не быть - его может перекрыть реализация виртуальной функции в производном классе. При `base.`-вызове из самой это реализации в производном классе вызов через *vtbl* приводил бы к рекурсивному вызову и зацикливанию (кстати, `base.`-вызовы можно делать из *любого метода уровня экземпляра* - я далеко не сразу это понял, что это разрешено). Так вот, по отношению к CLI, это выглядит некоторым “хаком” - разрешать вызовы виртуальных методов не виртуально, однако это разрешено, но с важным ограничением - такие не виртуальные `base.`-вызовы возможны только из классов, производных по отношению к классу, определяющему вызываемый виртуальный метод.

Время вернуться к коду выше. Опытный читатель наверняка уже догадался, что `base.`-вызовы там происходят не непосредственно коде в наследника `FooBase`, так как компилятор C# для анонимных методов (замыкающихся на локальные переменные)/итераторов генерирует скрытые от пользователя типы, в методы которого переносится код анонимного метода/всего итератора. Соответственно, вместе с остальным кодом туда могут переехать и `base.`-вызовы. Ничего страшного не произойдет и это они даже будут работать, но код перестанет верифицироваться `PEVerify`, что малоприятно. Именно так происходило в компиляторах C# до версии 4.0.

В компиляторе C# 4.0 это починили, достаточно простым решением - в класс-наследник добавляется метод-wrapper уровня экземпляра, которые уже на самом деле делает `base.`-вызов, то есть все ограничения CLI остаются соблюдены и код становится верифицируем. Однако чуваки из Редмонда, к сожалению, не подумали об извращенцах, которые додумаются создавать экземпляры делегатов из method group, квалифицированных через `base`. Компилятор C# в любом случае обращения использует wrapper-метод, поэтому созданный делегат реально указывает на wrapper-метод, а не на реальный метод, к которому происходит обращение через `base`.

Так как у класса `System.Delegate` переопределены методы `Equals`/`GetHashCode`, то для отписки метода на событие совершенно не нужен оригинальный экземпляр делегата, которым была произведена подписка. Однако в примере кода выше эквивалентность делегатов не срабатывает, так как они реально указывают на два разных метода уровня экземпляра, и отписки от события не происходит. Если таки необходимо получить нормальное поведение в таких ситуациях, то следует сделать ещё один метод уровня экземпляра, создающий и возвращающий экземпляр делегата из `base`-метода.

Остаётся надеяться, что здравомыслящему C#-программисту никогда не придёт в голову подписываться/отписываться от событий `base`-методами внутри лямбда-выражений или внутри итераторов (совсем уж ад).