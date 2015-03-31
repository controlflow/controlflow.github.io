---
layout: post
title: "Хитрый способ кэширования Expression Trees"
date: 2011-09-06 09:00:06
categories: 9869744363
tags: csharp expressions linq INotifyPropertyChanged mvvm
---
Достаточно часто в .NET-ориентированных блогах я нахожу различные механизмы, построенные с применением C# Expression Trees. Большинство из них предназначены для получения экземпляров `MethodInfo`/`PropertyInfo`/`FieldInfo` по выражениям доступа к методам/свойствам/полям соответственно (ну или просто именам членов классов). Это позволяет, например, при реализации интерфейса `INotifyPropertyChanged` уйти от строковых констант (`OnChanged(“PropertyName”)`) к лямбда-выражениям (`OnChanged(x => x.PropertyName)`), получая при этом проверки уровня компиляции и стойкость к автоматическим рефакторингам.

Проблема лишь в том, как формируются эти деревья во время выполнения. Например, такой код:

{% highlight C# %}
class Foo
{
  public int Value { get; set; }

  public Expression<Func<Foo, int>> Bar()
  {
    return x => x.Value;
  }
}
{% endhighlight %}

Разворачивается компилятором C# вот в такой (это не валидный код на C#, так как компилятор на уровне IL-кода использует специальные инструкции, позволяющие быстро получить `MethodInfo` по токену метода `get_Value()` , который является `get`-акцессором свойства `Value`. Примерно такой же код мог бы генерировать C#, если бы поддерживал аналоги `typeof()` для методов/свойств/полей):

{% highlight C# %}
class Foo
{
  public int Value { get; set; }

  public Expression<Func<Foo, int>> Bar()
  {
    var parameterExpression = Expression.Parameter(typeof(Foo), "x");
    return Expression.Lambda<Func<Foo, int>>(
      body:
        Expression.Property(
          expression: parameterExpression,
          propertyAccessor: (MethodInfo)
            MethodBase.GetMethodFromHandle(ldtoken(get_Value()))),
      parameters:
        new ParameterExpression[] { parameterExpression });
  }
}
{% endhighlight %}

Да, такая портянка исполняется при каждом формировании, казалось-бы, простого лямбда-выражения `x => x.Value`. При этом происходит несколько выделений памяти в куче, а так же множество проверок типов из которых формируется дерево выражения, что мягко говоря, не быстро.

В некоторых случаях этот overhead от формирование деревьев приемлем, но не всегда - например, реализацию интерфейса `INotifyPropertyChanged` используют для ViewModel’и в UI-паттерне MVVM (из мира WPF/Silverlight) именно из соображений производительности (вместо использования `DependencyProperty` и наследования от `DependencyObject`), а применение Expression Trees сводит бенефиты на нет.

Интересно то, что в мире делегатов, компилятор C# при отсутствии замыканий на внешний контекст использует [кэширование делегатов](http://controlflow.tumblr.com/post/1315695183/c-cachedanonymousmethoddelegate), но не существует аналогичного кэширования для деревьев выражений, не смотря на то, что они такие же неизменяемые, как и делегаты .NET (если у вас есть соображения насчёт причин, не позволяющих кэшировать ET так же, как делегаты - милости прошу ко мне в комментарии). О реализации такого кэширования с помощью “грязных хаков” и пойдёт речь далее.

В качестве “подопытного” возмём метод со всеми необходимыми проверками, возвращающий экземпляр `PropertyInfo` по выражению доступа к свойству некоторого класса:

{% highlight C# %}
using System;
using System.Linq.Expressions;
using System.Reflection;

public static class Property
{
  public static PropertyInfo Of<T, TProperty>(
    Expression<Func<T, TProperty>> propertyExpression)
  {
    if (propertyExpression == null)
      throw new ArgumentNullException("propertyExpression");

    var memberExpr = propertyExpression.Body as MemberExpression;
    if (memberExpr == null)
      throw new ArgumentException("MemberExpression expected");

    if (memberExpr.Member.MemberType != MemberTypes.Property)
      throw new ArgumentException("Property member expected");

    return (PropertyInfo) memberExpr.Member;
  }
}
{% endhighlight %}

Весь трюк заключается в том, что можно вместо дерева с типом `Expression<…>` требовать от пользователя обычный делегат с типом `Func< Expression<…> >`, то есть простой метод, возвращающий нужное дерево. Вместо `x => x.Property` следует передавать `() => x => x.Property`. Зачем? Во-первых весь код формирования дерева уезжает в код делегата, уменьшая размер клиентского кода (на уровне IL). Во-вторых делегат можно вызвать лишь один раз, получив дерево выражения и закэшировав его - так как делегат будет закэширован компилятором, то при всех вызовах экземпляр делегата будет одним и тем же и его можно использовать как ключ словаря { делегат => дерево выражения }.

Однако есть способ обойтись и безо всяких словарей. Итак кэшированный аналог выглядит следующим образом:

{% highlight C# %}
using System;
using System.Linq.Expressions;
using System.Reflection;

public static class Property
{
  public static PropertyInfo FromExpressionCached<T>(
    // вывода типов C# уже не хватает, поэтому используем object
    Func<Expression<Func<T, object>>> propertyExpression)
  {
    // если переданный делегат в замыкании хранит наш кэш
    var data = propertyExpression.Target as CachedData;
    if (data != null) return data.CachedValue;

    return FromImpl(propertyExpression); // иначе вычисляем PropertyInfo
  }

  private static PropertyInfo FromImpl<T>(
    Func<Expression<Func<T, object>>> propertyExpression)
  {
    // если у делегата нет замыкания,
    // то и у вложенного в него дерева выражения не должно быть
    if (propertyExpression.Target != null)
      throw new ArgumentException("Delegate should not have any closures.");
    if (!propertyExpression.Method.IsStatic)
      throw new ArgumentException("Delegate should be static.");

    var body = propertyExpression().Body; // вызываем таки делегат

    // из-за object у нас может быть тут лишний боксинг
    if (body.NodeType == ExpressionType.Convert &&
        body.Type     == typeof(object))
    {
      body = ((UnaryExpression) body).Operand;
    }

    var memberExpr = body as MemberExpression;
    if (memberExpr == null)
      throw new ArgumentException("MemberExpression expected");

    if (memberExpr.Member.MemberType != MemberTypes.Property)
      throw new ArgumentException("Property member expected");

    var propInfo = (PropertyInfo) memberExpr.Member;

    // раз делегат у нас статический, то он должен быть закэширован
    // компилятором в статическом поле типа, в котором он определён
    var declaringType = propertyExpression.Method.DeclaringType;
    foreach (var fieldInfo in declaringType
      .GetFields(BindingFlags.Static | BindingFlags.NonPublic))
    {
      // проходимся по всем статическим полям в поисках делегата
      if (ReferenceEquals(fieldInfo.GetValue(null), propertyExpression))
      {
        // нашёлся - создаём специальный holder для PropertyInfo
        var cached = new CachedData { CachedValue = propInfo };
        // заменяем делегат в поле на делегат на stub-метод
        var stub = new Func<Expression<Func<T, object>>>(cached.Stub<T>);
        fieldInfo.SetValue(null, stub);
        return propInfo;
      }
    }

    throw new InvalidOperationException("Delegate is not cached.");
  }

  // аналог closure-класса, хранящий закэшированное значение
  private sealed class CachedData
  {
    public PropertyInfo CachedValue { get; set; }

    public Expression<Func<T, object>> Stub<T>()
    {
      throw new InvalidOperationException("Should never be called");
    }
  }
}<br/>
{% endhighlight %}

То есть мы вызываем переданный делегат единожды и сохраняем вычисленное значение `PropertyInfo` прямо в поле кэшированного экземпляра делегата! А это значит, что при следующем вызове из клиентского кода нам передадут не исходный делегат, а нашу заглушку, из замыкания которой очень легко достать закэшированное значение (всего один type test)! Не смотря на массивность кода и рефлексию, работает эта штука по сравнению с Expression Trees просто реактивно:

{% highlight C# %}
using System;
using System.Diagnostics;
using System.Threading;

static class Program
{
  static void Main()
  {
    Thread.CurrentThread.Priority = ThreadPriority.Highest;
    const int count = 100000;

    var sw = Stopwatch.StartNew();
    for (var i = 0; i < count; i++)
    {
      var p = Property.FromExpression((Stopwatch _) => _.Elapsed);
      GC.KeepAlive(p);
    }

    Console.WriteLine("expr: {0}", sw.Elapsed);
    sw.Reset();
    sw.Start();

    for (var i = 0; i < count; i++)
    {
      var p = Property.FromExpressionCached<Stopwatch>(() => _ => _.Elapsed);
      GC.KeepAlive(p);
    }

    Console.WriteLine("hack: {0}", sw.Elapsed);
  }
}
{% endhighlight %}

На лаптопе с i3 @ 2533Mhz показывает в среднем следующие результаты, почти три порядка разницы:

```
expr: 00:00:01.0867601
hack: 00:00:00.0014079
```
p.s. Ради бога, не используйте это решение в production. Весь этот способ - завязка на implementation details компилятора (кэширование делегатов), мутирование чужих статических переменных и прочее безобразие, непонятно как работающее в многопоточной среде. Код приведён исключительно в образовательных целях и лишь показывает, что кэширование Expression Trees имело бы место в C#.