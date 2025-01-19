---
layout: post
title: "Великий и могучий Delegate.CreateDelegate"
date: 2011-01-17 16:19:00
author: Aleksandr Shvedov
tags: csharp delegate createdelegate dynamicmethod begininvoke ref valuetype
---
Сегодня хотелось бы поделиться мыслями относительно замечательного метода `System.Delegate.`[`CreateDelegate`](http://msdn.microsoft.com/en-us/library/9tz542wy.aspx), доступного ещё с первых версий .NET Framework. Назначение - создать экземпляр делегата динамически по типу делегата (в виде `System.Type`) и методу, заданному в виде строкового имени или экземпляра `System.Reflection.MethodInfo`. Интерес представляет то, как данный метод позволяет сопоставить те или иные сигнатуры методов различным типам делегатов.

Давайте определим класс и структуру следующего вида:

```c#
class FooClass {
  public static void StaticBar(object x) { }
  public string InstanceBar(int x) { return "abc"; }
}

struct FooStruct {
  public void InstanceBoo(int x) { }
}
```

И посмотрим делегаты какого типа мы можем создать:

* **Делегат из статического метода**

Так же как статически в C# из метода `FooClass.StaticBar` можно создать делегат типа `Action<object>`:

```c#
Action<object> staticBar = FooClass.StaticBar;
```

Можно аналогично использовать и `Delegate.CreateDelegate`:

```c#
var staticBar = (Action<object>)
  Delegate.CreateDelegate(
    type:   typeof(Action<object>),
    method: typeof(FooClass).GetMethod("StaticBar"));
```

* **Делегат из метода экземпляра**

Опять же, аналогично статическому поведению C#:

```c#
Func<int, string> instanceBar1 = new FooClass().InstanceBar;
```

Можно создавать делегаты из методов уровня экземпляра, указывая через дополнительный параметр `firstArgument` экземпляр объекта, для которого будет вызываться выбранный метод экземпляра:

```c#
var instanceBar = (Func<int, string>) Delegate.CreateDelegate(
  type:   typeof(Func<int, string>),
  method: typeof(FooClass).GetMethod("InstanceBar"),
  firstArgument: new FooClass()); /* <== */
```

Помимо методов уровня экземпляра классов, поддерживаются и методы экземпляров типов-значений, при этом структура будет подвергнута боксингу:

```c#
var instanceBoo = (Action<int>) Delegate.CreateDelegate(
  type:   typeof(Action<int>),
  method: typeof(FooStruct).GetMethod("InstanceBoo"),
  firstArgument: new FooStruct()); /* <== */
```

* **Делегат из метода с отличающимся типом параметров**

C# статически поддерживает контравариантность типов параметров при создании экземпляров делегатов из *method group*. Например, возможно подписаться методом с сигнатурой:

```c#
void Foo(object sender, EventArgs e)
```

на событие, ожидающее делегат типа:

```c#
void PropertyChangedEventHandler(object sender, PropertyChangedEventArgs e)
```

Так как класс `PropertyChangedEventArgs` является наследником класса `EventArgs`. Аналогично допустимо создать такой делегат, так как `string` является наследником `object`:

```c#
Action<string> contravariantParameterType = FooClass.StaticBar;
```

`Delegate.CreateDelegate` повторяет статическое поведение C# и тоже поддерживает контравариантность:

```c#
var contravariantParameterType = (Action<string>) Delegate.CreateDelegate(
  type:   typeof(Action<string>),
  method: typeof(FooClass).GetMethod("StaticBar"));
```

* **Делегат из метода с отличающимся типом возвращаемого значения**

Аналогично C# поддерживает ковариантность типа возвращаемого значения:

```c#
Func<int, object> covariantReturnType = new FooClass().InstanceBar;
```

`Delegate.CreateDelegate` не отстаёт:

```c#
var covariantReturnType = (Func<int, object>) Delegate.CreateDelegate(
  type:   typeof(Func<int, object /* <== */>),
  method: typeof(FooClass).GetMethod("InstanceBar"),
  firstArgument: new FooClass());
```

* **Делегат из метода экземпляра ссылочного типа с открытым первым аргументом**

Тут всё становится интереснее, так как C# не позволяет создавать такие делегаты статически. Дело в том, что если не указывать экземпляр через параметр `firstArgument` и подобрать тип делегата таковым, чтобы первый аргумент делегата был ссылочного типа, определяющего данный метод, то можно создать экземпляр делегата так, как если бы метод экземпляра был статическим:

```c#
var instanceBarAsStatic = (Func<FooClass, int, string>) Delegate.CreateDelegate(
  type:   typeof(Func<FooClass /* <== */, int, string>),
  method: typeof(FooClass).GetMethod("InstanceBar"));
```

А затем вызывать делегат для различных экземпляров:

```c#
var foo1 = new FooClass();
var foo2 = new FooClass();

instanceBarAsStatic(foo1, 1);
instanceBarAsStatic(foo2, 2);
instanceBarAsStatic(null, 3); // NRE?
```

Но тут надо быть очень осторожным, так как в случае третьего вызова проверка экземпляра (`this`) на `null` перестаёт действовать:

![]({{ site.baseurl }}/images/delegate-create.png)

Будьте аккуратны ;)

* **Делегат из статического метода с закрытым (фиксированным) первым аргументом ссылочного типа**

Теперь провернём предыдущий трюк наоборот: укажем `firstArgument` в случае создания делегата из статического метода и уберём из типа делегата первый аргумент:

```c#
var staticBarWithFixedArg = (Action) Delegate.CreateDelegate(
  type:   typeof(Action),
  method: typeof(FooClass).GetMethod("StaticBar"),
  firstArgument: new object()); /* <== */
```

Теперь экземпляр `new object()` “запомнится” внутри экземпляра делегата и будет автоматически подставляться как первый аргумент при каждом вызове. Для того, чтобы создать такой делегат, первый аргумент *обязан* быть ссылочного типа. Фактически мы получили каррирование первого аргумента метода.

* **Делегат из метода экземпляра типа-значения с открытым первым аргументом**

Возможность создавать делегаты такого типа я обнаружил совсем недавно, просто размышляя об устройстве методов уровня экземпляра, определённых для структур C#. На самом деле практически во всех методах экземпляров `this` представляет собой обычный `ref`-параметр (или `out`-параметр в конструкторах структур), которому ещё и можно присваивать! Раз `this` - это `ref`-параметр, то логично было попробовать создать тип делегата соответствующей сигнатуры (все типы `Action`- и `Func`-делегатов не предполагают наличие `ref`-/`out`-параметров):

```c#
delegate void FooStructBooRef(ref FooStruct foo, int x);
```

И попробовать создать делегат, не указывая параметр `firstArgument`:

```c#
var instanceBooAsStaticWithRef = (FooStructBooRef) Delegate.CreateDelegate(
  type:   typeof(FooStructBooRef /* <== */),
  method: typeof(FooStruct).GetMethod("InstanceBoo"));
```

Оказалось, что это работает и можно без проблем подменять структуру при вызове:

```c#
var foo1 = new FooStruct();
var foo2 = new FooStruct();

instanceBooAsStaticWithRef(ref foo1, 1);
instanceBooAsStaticWithRef(ref foo2, 2);
```

Из нюансов тут следует отметить то, что можно создать и тип делегата с первым `out`-параметром (для рантайма не существует различия между `ref`- и `out`-параметрами кроме атрибута, который фактически использует только компилятор C#), но нельзя создать такие делегаты из виртуальных методов `GetHashCode`, `Equals` и `ToString`, унаследованных от `System.Object`, так как вызов данных методов всегда требуют боксинга типов-значений.

**Бонус**

Хочется описать один workaround, раз пост посвящён делегатам, то пусть будет здесь. Однажды я столкнулся со следующей проблемой:

```c#
Expression<Func<string>> expr = () => "abc";
Func<string> func = expr.Compile();

// ArgumentException:
// The object must be a runtime Reflection object.
func.BeginInvoke(
  a => Console.WriteLine(func.EndInvoke(a)),
  null);
```

Оказывается среда выполнения не поддерживает методы `BeginInvoke`/`EndInvoke` делегатов, созданных с помощью класса `System.Reflection.Emit.DynamicMethod` (который используют Expression Trees в .NET).

Исправить достаточно легко, надо лишь обернуть `DynamicMethod-`делегат в другой делегат из обычного метода и вызывать у него `BeginInvoke`, но мне не были заранее известны сигнатуры делегатов и это было затруднительно. Я решил проблему очень просто - создал делегат прямо из метода `Invoke` экземпляра другого делегата:

```c#
Expression<Func<string>> expr = () => "abc";
Func<string> func = expr.Compile();

func = (Func<string>) Delegate.CreateDelegate(
  type:   typeof(Func<string>),
  method: typeof(Func<string>).GetMethod("Invoke"),
  firstArgument: func);

func.BeginInvoke( // OK now
  a => Console.WriteLine(func.EndInvoke(a)),
  null);
```

Быть может кому-нибудь это пригодится.