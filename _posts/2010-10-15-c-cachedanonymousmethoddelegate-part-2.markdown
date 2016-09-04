---
layout: post
title: "C# CachedAnonymousMethodDelegate (part 2)"
date: 2010-10-15 11:26:07
tags: csharp cache delegate anonymous
---
На самом деле, кэширование экземпляров делегатов из статических методов - не единственный случай применения подобной оптимизаций компилятором C#.

Рассмотрим такой код:

```c#
static void ShowDevelopersBySkill(IEnumerable teams, int level) {
  foreach (var team in teams) {
    team.ShowBy(dev => dev.Skill >= level);
  }
}
```

Здесь лямбда-выражение замыкается на внешний контекст - параметр метода. Компилятор C# в данном случае генерирует closure-класс, который выглядит примерно так (имена изменены для большей читаемости):

```c#
[CompilerGenerated]
private sealed class DisplayClass1 {
  public int level;

  public bool ShowDevelopersBySkill(Developer dev) {
    return dev.Skill >= level;
  }
}
```

Один раз замкнувшись на параметр, мы продлеваем его срок жизни на неопределённый срок, поэтому все обращения к параметру внутри метода заменяются на обращение к полю closure-класса, инициализируемому в во время создания экземпляра closure-класса.

В первом листинге кода можно обратить внимание на то, что требуется создавать экземпляр делегата для вызова `FilterBy()` на каждой итерации внешнего цикла. Однако реально все создаваемые делегаты будут замыкаться на одну и ту же переменную level и могут разделять между собой один и тот же closure-класс, а значит можно обойтись и одним экземпляром делегата. Компилятор C# обнаруживает данную ситуацию и генерирует следующий код:

```c#
static void ShowDevelopersBySkill(IEnumerable<Team> teams, int level) {
  Func<Developer, bool> CachedAnonymousMethodDelegate1 = null;
  var closureLocal = new DisplayClass1();
  closureLocal.level = level;

  foreach (var team in teams) {
    if (CachedAnonymousMethodDelegate1 == null) {
      CachedAnonymousMethodDelegate1 =
        new Func<Developer, bool>(closureLocal.ShowDevelopersBySkill);
    }

    team.ShowBy(CachedAnonymousMethodDelegate1);
  }
}
```

То есть все вызовы `FilterBy()` на каждой итерации цикла на самом деле разделяют один и тот же экземпляр делегата, создаваемый при первой итерации и сохраняемый в локальной переменной.

Однако данная оптимизация неприменима в общем случае для делегатов на любые методы экземпляров, компилятор C# идёт на такие ухищрения только для анонимных методов и лямбда-выражений, когда может быть уверен, что создаваемые делегаты будут создаваться несколько раз и будут разделять между собой один и тот же closure-класс.