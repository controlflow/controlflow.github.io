---
layout: post
title: "Design and evolution of properties in C# (part 8)"
date: 2025-02-02 13:44:00
author: Aleksandr Shvedov
tags: csharp properties design
---

## Time has passed

Последний пост из этой серии вышел целых 10 лет назад, фух! С тех пор вышло целых 7 версий языка C#, со множеством языковых фич застрагивающих свойства. Свойства стали ещё более сложным языковым средством, что сложно было представить во времена C# 6.0, когда дизайн двигался скорее в сторону упрощения и ортогональности языка. В следующих постах я постараюсь собрать все нововведения языка C#, повлиявшие на дизайн свойств. Начнём с C# 7, вышедшим в 2017 году.

### C# 7: expression-bodied accessors

C# 6 ввёл новый синтаксис для задания тел членов классов - expresson-bodied members. Однако новый синтаксис был доступен только для всего свойства и применим только для get-only свойств. C# 7 добавил синтаксис 

```c#
public class Person
{
    string _name;

    public string Name
    {
        get { return _name; }
        set
        {
            if (value == null) throw new ArgumentNullException("value");
            _name = value;
        }
    }
}
```

```c#
class C
{
    public int P => e;
    public int P { get => e; }
    public int P { get =}
}
```

### C# 7: throw expressions


### C# 7: ref returns

```c#
class C
{
    public ref int Prop
    {
        get {  }
    }
}
```

### C# 7: pattern matching

```c#
public int Property { get; set; }

[Attribute(Property = 42)]

value.Property = 42;
```

```c#
if (value is { Property: 42 }) { /*...*/ }
```