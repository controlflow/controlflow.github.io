---
layout: post
title: "C# delegate instances caching (part 2)"
date: 2010-10-15 11:26:07
author: Aleksandr Shvedov
tags: csharp cache delegate anonymous
---
The delegate caching described in the previous post is not limited to non-capturing lambdas compiled into static methods.

Consider the following code:

```c#
static void ShowDevelopersBySkill(IEnumerable<Team> teams, int level)
{
  foreach (var team in teams)
  {
    team.ShowBy(dev => dev.Skill >= level);
  }
}
```

Here, the lambda captures a method parameter. The C# compiler generates a closure class that looks approximately like this, with names simplified for readability:

```c#
[CompilerGenerated]
private sealed class DisplayClass1
{
  public int level;

  public bool ShowDevelopersBySkill(Developer dev)
  {
    return dev.Skill >= level;
  }
}
```

Capturing the parameter allows it to outlive the method invocation. The compiler moves its storage into a field of the closure object, initializes that field from the argument, and redirects accesses to the captured parameter through the field.

At first glance, the call to `ShowBy()` in the loop appears to require a new delegate on every iteration. Within a single method invocation, however, all these delegates capture the same `level` variable and refer to the same closure object. One delegate instance is therefore sufficient. The C# compiler recognizes this case and generates code equivalent to the following:

```c#
static void ShowDevelopersBySkill(IEnumerable<Team> teams, int level)
{
  Func<Developer, bool> CachedAnonymousMethodDelegate1 = null;
  var closureLocal = new DisplayClass1();
  closureLocal.level = level;

  foreach (var team in teams)
  {
    if (CachedAnonymousMethodDelegate1 == null)
    {
      CachedAnonymousMethodDelegate1 =
        new Func<Developer, bool>(closureLocal.ShowDevelopersBySkill);
    }

    team.ShowBy(CachedAnonymousMethodDelegate1);
  }
}
```

All calls to `ShowBy()` within the loop share one delegate instance. It is created on the first iteration and cached in a local variable for the remaining iterations. The cache is local to this invocation of `ShowDevelopersBySkill()`.

This is not a general optimization for delegates bound to arbitrary instance methods. The compiler applies it to anonymous methods and lambda expressions when it can determine that repeated evaluations will produce delegates referring to the same closure object.