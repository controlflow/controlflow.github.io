---
layout: post
title: "Мемоизация функций с помощью аспекта PostSharp"
date: 2010-12-19 14:29:00
categories: 2372528624
tags: csharp postsharp aop memoize aspect
---
Недавно поставил поиграться [PostSharp](http://www.sharpcrafters.com/) 2.0, стало интересно посмотреть на инфраструктуру и возможности, оценить API определения аспектов и удобство отладки. Лично на меня впечатление PostSharp произвёл сугубо положительное (не смотря на community edition, различий от полной платной версии минимум), установился просто, для использования достаточно лишь добавить в проект ссылку на `PostSharp.dll`.

В качестве задачи я выбрал мемоизацию функций, так как единственный [пример](http://dpatrickcaldwell.blogspot.com/2009/02/memoizer-attribute-using-postsharp.html) в Сети оказался очень уныл (как можно было вообще догадаться клеить строковое представление всех аргументов в одну строку и использовать её как ключ словаря) и в задаче есть пространство для интересных оптимизаций.

Аспекты PostSharp на самом деле являются классами, унаследованными от класса `System.Attribute`, то есть обычными атрибутами. Инфраструктура PostSharp предлагает вам несколько базовых классов, таких как:

* `MethodInterceptionAspect` - перехват вызовов методов;
* `LocationInterceptionAspect` - перехват обращений к свойствам и полям;
* `OnMethodBoundaryAspect` - перехват моментов входа и выхода из метода;
* `OnExceptionAspect` - перехват вызовов методов, выбросивших исключение;
* `EventInterceptionAspect` - перехват подписки на события.

Мы будем перехватывать вызовы методов. Кроме того, сразу следует обратить внимание, что у аспектов есть время жизни - бывают аспекты уровня типа и уровня экземпляра. По умолчанию, аспекты унаследованные от `MethodInterceptionAspect` являются аспектами уровня типа, а это приведёт к тому, что если мы применим мемоизацию к методу экземпляра, то кэш аргументов и возвращаемых значений будет один на все экземпляры - это скорее всего не верно (будем считать что `this` - это обычный аргумент метода и он должен участвовать в поиске по кэшу), поэтому наш аспект должен быть уровня экземпляра. Для этого следует реализовать им интерфейс `IInstanceScopedAspect` (тогда экземпляр аспекта будет создаваться при создании экземпляра класса, на метод экземпляра которого применён аспект). Итак:

{% highlight C# %}
/// <summary>
/// Аспект, производящий мемоизацию метода, отмечаемого данным
/// атрибутом. Методы с ref-/out-параметрами не поддерживаются.
/// </summary>
[Serializable, AttributeUsage(AttributeTargets.Method)]
public sealed class MemoizeAttribute : MethodInterceptionAspect, IInstanceScopedAspect
{
    // Указывает, должен ли метод корректно поддерживать работу в многопоточной среде.
    public bool IsThreadSafe { get; set; }
{% endhighlight %}

Обратите внимание, что все аспекты PostSharp (и вложенный определния классов) должны быть отмечены атрибутом `[Serializable]`. Свойство `IsThreadSafe` становится обычным именованным параметром атрибута и позволит пользователю запрашивать поддержку корректной работы мемоизации в многопоточной среде. Реализовать поддержку `ref`-/`out`-параметров возможно, но не хотелось бы нетривиально усложнять реализацию в данном посте, поэтому от их поддержки просто откажемся.

Вот только как контролировать использование атрибута и не позволять применять его на методы, для которых он не имеет смысла (методы без возвращаемого значения или вовсе без параметров)? Специально для этого в PostSharp предусмотрен виртуальный метод `CompileTimeValidate()`, переопределяя который можно написать свою логику валидации использования атрибута во время компиляции (переопределение данного метода может вернуть `false` и тогда аспект просто не будет применён без сообщений об ошибках):

{% highlight C# %}
/// <summary>
/// Процедура валидации использования аспекта мемоизации.
/// </summary>
public override bool CompileTimeValidate(MethodBase method) {
  var mi = (MethodInfo) method;
  if (mi.ReturnType == typeof(void)) {
    throw new InvalidOperationException(
      "Аспект следует применять только на методы, возвращающие значение.");
  }

  var paremeters = mi.GetParameters();
  if (paremeters.Length == 0) {
    throw new InvalidOperationException(
      "Аспект следует применять только на методы, имеющие параметры.");
  }

  foreach (var parameter in paremeters) {
    if (parameter.IsIn || parameter.IsOut) {
      throw new InvalidOperationException(
        "Аспект невозможно использовать с методами, обладающими ref-/out-параметрами.");
    }
  }

  return true;
}
{% endhighlight %}

Единственную проблему здесь создаёт тот факт, что по сообщению об ошибке из PostSharp в Visual Studio невозможно сразу переместиться на место некорректного применения аспекта, что уныло. Вроде функционал для этого есть, но пока не удалось с ним разобрался.

Теперь немного отвлечёмся от PostSharp и подумаем как будем всё это дело кэшировать. Дело в том, что при перехватывании вызовов методов, PostSharp предоставляет нам доступ к переданным параметрам и возвращаемому значению через слабо типизированные свойства и коллекции класса `MethodInterceptionArgs`, а хранить их хотелось бы в строго типизированном кэше. Давайте соорудим такую штуку:

{% highlight C# %}
[Serializable]
abstract class MemoCache
{
  public abstract bool TryResolve(object arg, out object result);
  public abstract void AppendItem(Arguments arg, int index, object result);
}
{% endhighlight %}

То есть предоставим слабо типизированный интерфейс для извлечения и добавления в кэш. Возникает вопрос - для извлечения из кэша предусмотрен метод, получающим *один* аргумент, а ведь у метода их может быть несколько. Идея в том, что в качестве значений *кэша по первому аргументу* можно хранить *кэши по второму аргументу* и так далее. Данный подход оптимизирует занимаемое место, более производителен (не надо все аргументы складывать в одну структуру и считать её хэш, можно быстрее определить промах кэша) и более благоприятен для многопоточных сред (получается несколько раздельно блокируемых кэшей). Давайте опишем наследника данного класса, параметризованного типами-параметрами:

{% highlight C# %}
[Serializable]
abstract class MemoCache<T, TResult> : MemoCache
{
  static readonly Func<MemoCache> NestedCacheFactory;

  static MemoCache() {
    // если элементами кэша данного типа
    // являются другие вложенные кэши
    if (typeof(TResult).IsSubclassOf(typeof(MemoCache))) {
      NestedCacheFactory = GetCacheFactory(typeof(TResult));
    }
  }

  protected abstract void AppendImpl(T arg, TResult result);

  public sealed override void AppendItem(Arguments arg, int index, object result) {
    if (NestedCacheFactory == null) {
      // тривиально добавляем в кэш
      AppendImpl((T) arg[index], (TResult) result);
    } else {
      // создаём экземпляр вложенного кэша
      var nested = NestedCacheFactory();
      AppendImpl( // и добавляем его в кэш
        (T) arg[index],
        (TResult) (object) nested);

      // кэшируем следующий аргумент
      nested.AppendItem(arg, index + 1, result);
    }
  }
}
{% endhighlight %}

Назначение данного класса следующее: мы вводим типы ключа и значения через типы-параметры класса и переопределяем логику добавления в кэш. В статическом конструкторе определяем, являются ли значения данного кэша другими кэшами и если это так, получаем из описанной ниже функции `GetCacheFactory()` делегат для создания экземпляров данного кэша. Логика добавления определяется следующим образом: если значениями данного кэша являются другие кэши, то создаём экземпляр вложенного кэша (через делегат-фабрику), добавляем в себя пару (*текущий_аргумент*; *вложенный_кэш*) и добавляем во вложенный кэш следующий аргумент и возвращаемое значение. Иначе просто добавляем в себя пару (*аргумент*; *возвращаемое_значение*).

То есть кэш для метода `int F(int, string, decimal)` будет представлять собой экземпляр типа:

{% highlight C# %}
SomeCache<int, SomeCache<string, SomeCache<decimal, int>>>
{% endhighlight %}

Где `SomeCache<,>` - наследник `MemoCache<,>`, определяющий как именно будут храниться кэшированные значения. То есть при добавлении в самый внешний кэш, он должен создать кэш второго уровня вложенности и поставить ему в соответствие первый аргумент типа `int`. Кэш второго уровня типа должен создать кэш третьего уровня и поставить ему в соответствие второй аргумент типа `string`. Кэш третьего уровня должен просто поставить в соответствие третий аргумент типа `decimal` и возвращаемое значение типа `int`.

Давайте определим такой тип как `SomeCache<,>`, например, использующий кэш на базе обычного словаря `Dictionary<,>`:

{% highlight C# %}
/// <summary>
/// Вариант кэша на базе обычного словаря.
/// </summary>
[Serializable]
sealed class DictionaryCache<T, TResult> : MemoCache<T, TResult>
{
  readonly Dictionary<T, TResult> cache = new Dictionary<T, TResult>();

  public static MemoCache CreateInstance() {
    return new DictionaryCache<T, TResult>();
  }

  public override bool TryResolve(object arg, out object result) {
    TResult value;
    if (cache.TryGetValue((T) arg, out value)) {
      result = value;
      return true;
    } else {
      result = null;
      return false;
    }
  }

  protected override void AppendImpl(T arg, TResult result) {
    cache.Add(arg, result);
  }
}
{% endhighlight %}

Тут всё предельно просто. Обратите внимание на статический метод создания экземпляров данного типа кэша. Именно из этого метода создаётся делегат-фабрика методом `GetCacheFactory()`, код которого приведён ниже:

{% highlight C# %}
/// <summary>
/// Возвращает фабрику создания экземпляров кэша по типу.
/// </summary>
static Func<MemoCache> GetCacheFactory(Type cacheType)
{
  // ищем метод "public static MemoCache CreateInstance()"
  var methodInfo = cacheType.GetMethod(
    "CreateInstance", BindingFlags.Static | BindingFlags.Public);

  // и создаём из него делегат для быстрого создания экземпляров
  return (Func<MemoCache>)
    Delegate.CreateDelegate(typeof(Func<MemoCache>), methodInfo);
}
{% endhighlight %}

Для корректной работы этот метод должен быть определён во всех наследниках `MemoCache<,>`. Давайте определим ещё одного наследника, на базе коллекции `ConcurrentDictionary<,>` из .NET 4.0:

{% highlight C# %}
/// <summary>
/// Вариант кэша на базе конкурентного словаря.
/// </summary>
[Serializable]
sealed class ConcurrentCache<T, TResult> : MemoCache<T, TResult>
{
  readonly ConcurrentDictionary<T, TResult> cache = new ConcurrentDictionary<T, TResult>();

  public static MemoCache CreateInstance() {
    return new ConcurrentCache<T, TResult>();
  }

  public override bool TryResolve(object arg, out object result) {
    TResult value;
    if (cache.TryGetValue((T) arg, out value)) {
      result = value;
      return true;
    } else {
      result = null;
      return false;
    }
  }

  protected override void AppendImpl(T arg, TResult result) {
    cache.AddOrUpdate(arg, result, (_, x) => x);
  }
}
{% endhighlight %}

Осталось совсем немного. Требуется метод, формирующий тип самого внешнего типа в виде экземпляра `System.Type` по определению метода, подвергаемого мемоизации:

{% highlight C# %}
/// <summary>
/// Создаёт тип кэша, соответствующий типам параметров
/// заданного метода и требованиям к многопоточной работе.
/// </summary>
Type GetRootCacheType(MethodInfo method) {
  Debug.Assert(method != null);

  var parameters = method.GetParameters();
  var resultType = method.ReturnType;

  // определяем тип используемого кэша
  var cacheType = IsThreadSafe ? typeof(ConcurrentCache<,>) : typeof(DictionaryCache<,>);

  // перебираем параметры с конца
  for (int i = parameters.Length - 1; i >= 0; i--) {
    // формируем тип "Cache<T1, Cache<T2, Cache<T3, TResult>>>",
    // в котором типы T1, T2, T3 соответствуют параметрам метода:
    resultType = cacheType.MakeGenericType(parameters[i].ParameterType, resultType);
  }

  return resultType;
}
{% endhighlight %}

Данный метод проверяет свойство `IsThreadSafe` аспекта и использует различный тип кэша, в зависимости от выбора пользователя. Вы можете легко определить собственные типы кэша, например, на базе очередей или каких-нибудь коллекций, ограниченных по объёму или по времени жизни объекта, и добавить их в логику формирования типа кэша.

Давайте наконец определим в аспекте поле для кэша перового уровня и логику перехвата вызова метода:

{% highlight C# %}
MemoCache cacheRoot;

/// <summary>
/// Обработчик вызова мемоизируемого метода.
/// </summary>
public override void OnInvoke(MethodInterceptionArgs args) {
  MemoCache argCache = this.cacheRoot;
  Arguments arguments = args.Arguments;
  object result = null;
  int index = 0;

  LookupArg: // последовательно извлекаем значения из кэшей
  if (argCache.TryResolve(arguments[index++], out result)) {
    // если не последний аргумент, то кэш
    if (index < arguments.Count)
    {
        argCache = (MemoCache) result;
        goto LookupArg; // да, это goto!
    }

    args.ReturnValue = result;
  } else { // промах кэша, вызываем метод и кэшируем
    args.Proceed();
    argCache.AppendItem(arguments, index - 1, args.ReturnValue);
  }
}
{% endhighlight %}

Тут всё предельно просто (мне здесь `goto` почему-то куда больше нравится, чем циклы с выходом по `return;`), объяснять нечего. Небольшим бенефитом тут является то, что в случае промаха у нас есть ссылка именно на тот кэш, в котором не нашлось переданного аргумента и не надо искать место для добавления.

Осталось определить метод статической инициализации аспекта, изучающий мемоизируемый метод и подготавливающий фабрику для создания кэшей самого внешнего уровня (корневых кэшей):

{% highlight C# %}
static Func<MemoCache> RootCacheFactory;

/// <summary>
/// Статическая инициализация аспекта,
/// создаёт кэш для мемоизации статических методов.
/// </summary>
public override void RuntimeInitialize(MethodBase method) {
  var type = GetRootCacheType((MethodInfo) method);
  RootCacheFactory = GetCacheFactory(type);

  if (method.IsStatic)
    this.cacheRoot = RootCacheFactory();

  base.RuntimeInitialize(method);
}
{% endhighlight %}

Данный метод вызывается один раз для каждого метода, на который применяется аспект мемоизации. Если метод статический, то тут же создаётся экземпляр корневого кэша. Для методов уровня экземпляра PostSharp использует реализацию интерфейса `IInstanceScopedAspect`:

{% highlight C# %}
/// <summary>
/// Создание экземпляра аспкета уровня экземпляра, попадает в конструктор типа,
/// экземплярный метод которого подвергается аспекту мемоизации.
/// </summary>
public object CreateInstance(AdviceArgs adviceArgs) {
  return new MemoizeAttribute {
      IsThreadSafe = this.IsThreadSafe
  };
}

/// <summary>
/// Инициализация аспекта уровня экземпляра.
/// </summary>
public void RuntimeInitializeInstance() {
  this.cacheRoot = RootCacheFactory();
}
{% endhighlight %}

Реализация `CreateInstance()` создаёт экземпляр аспекта уровня экземпляра (просто копирует все данные из аспекта уровня типа), а `RuntimeInitializeInstance()` инициализирует корневой кэш этого экземпляра аспекта.

Всё, можно тестировать аспект на всеми любимых факториалах:

{% highlight C# %}
class Foo {
  [Memoize]
  static int StaticFact(int x) {
      Console.WriteLine("=> StaticFact({0}) call", x);

    if (x == 0) return 1;
    return x * StaticFact(x - 1);
  }

  [Memoize(IsThreadSafe=true)]
  int InstanceFact(int x) {
    Console.WriteLine("=> InstanceFact({0}) call", x);

    return Enumerable
      .Range(1, x)
      .Aggregate(1, (a, b) => a * b);
  }

  static void Main() {
    Action<string, object> wl = Console.WriteLine;

    wl("SataticFact(2) = {0}", StaticFact(2));
    wl("SataticFact(2) = {0}", StaticFact(2));
    wl("SataticFact(7) = {0}", StaticFact(7));
    wl("SataticFact(7) = {0}", StaticFact(7));

    Console.WriteLine();

    var a = new Foo();
    var b = new Foo();

    wl("a.InstanceFact(7) = {0}", a.InstanceFact(7));
    wl("a.InstanceFact(7) = {0}", a.InstanceFact(7));

    wl("b.InstanceFact(7) = {0}", b.InstanceFact(7));
    wl("b.InstanceFact(7) = {0}", b.InstanceFact(7));
  }
}
{% endhighlight %}

Обратите внимание на различие в реализации. Вывод данного примера:

    => StaticFact(2) call
    => StaticFact(1) call
    => StaticFact(0) call
    SataticFact(2) = 2
    SataticFact(2) = 2
    => StaticFact(7) call
    => StaticFact(6) call
    => StaticFact(5) call
    => StaticFact(4) call
    => StaticFact(3) call
    SataticFact(7) = 5040
    SataticFact(7) = 5040

    => InstanceFact(7) call
    a.InstanceFact(7) = 5040
    a.InstanceFact(7) = 5040
    => InstanceFact(7) call
    b.InstanceFact(7) = 5040
    b.InstanceFact(7) = 5040

Красиво и очень просто, не правда ли? Стоит отметить, что данная мемоизация не считает исключения, выбрасываемые мемоизируемым методом, за возвращаемое значение и не кэширует их, а просто пропускает в клиентский код.

Полный код этого поста доступен [здесь](http://pastebin.com/Mk6NuUMH). Happy PostSharping!