---
layout: post
title: "Измерение времени исполнения кода в F#"
date: 2011-02-05 17:29:00
categories: 3123189766
tags: fsharp measure stopwatch printf sprintf threadpriority gc
---
Наверняка многие из вас, дорогие читатели, писали на многих языках программирования строчки, подобные этим:

{% highlight fsharp %}
let timer = System.Diagnostics.Stopwatch.StartNew()

for i = 0 to 100500 do
    someTask()

timer.Stop()
printfn "elapsed=%O" timer.Elapsed
{% endhighlight %}

Писать такую портянку для того, чтобы прикинуть производительность того или иного кусочка кода, обычно лень. Более того, данный код имеет недостатки и возможно улучшить актуальность возвращаемых им результатов. Основные направления для улучшений:

* Необходимо контроллировать, чтобы код тестировался *без подключенного отладчика* (вдруг вы забудете об этом?).
* Необходимо удостовериться, что код сборки был собран с атрибутом, разрешающим *оптимизации JIT-компилятора* (*RELEASE*-сборка со включенными оптимизациями).
* Перед тестированием следует задавать *высокий приоритет *тестирующему потоку.
* До тестирования следует вызывать *сборку мусора* чтобы тестовые фрагменты кода были изначально в более одинаковых условиях.
* Обычно лениво подбирать вручную *количество итераций*, необходимое для получения актуальных результатов (необходимо добиться достаточно длительного выполнения тестов).
* Можно *корректировать* результаты тестов если внести дополнительный *пустой тест*, тем самым измерив время, которое тратится на тестирующую инфраструктуру.
* Иногда имеет смысл сделать *"прогревочную" итерацию*, для того чтобы тестируемый код произвёл какие-либо первоначальные инициализации.
* Было бы удобно последовательно запускать тесты несколько раз и вычислять *средний*, *минимальный* и *максимальный* результаты.
* Удобно иметь хоть какое-то *табличное представление* результатов.
* Удобно видеть *прогресс* тестирования и иметь возможность *отменить* тестирование в любой момент.

Так как я добрый и позаботился о вас, то вот сигнатура:

{% highlight fsharp %}
module Measure

/// Настройки измерения производительности
[<NoEquality; NoComparison>]
type TestOptions =
   { /// Запуск сборщика мусора до и после каждого теста.
     perRunGC: bool
     /// Сбор статистики о количестве сборок мусора.
     collectGCStat: bool
     /// Повышение приоритета текущему потоку.
     highPriority: bool
     /// Проверка настроек среды, таких как задействованные
     /// JIT-оптимизации и запуск без отладчика.
     checkTestEnv: bool
     /// Отображение полосы прогресса тестирования
     showProgress: bool
     /// Корректировка результатов с учётом влияния
     /// тестирующей инфраструктуры
     impactCorrect: bool
     /// Прогревочный запуск
     warmIteration: bool
     /// Очистка консоли перед выводом
     /// очередной таблицы результатов.
     clearConsole: bool
     /// Показывать средние результаты.
     showAverage: bool
     /// Показывать минимальные результаты.
     showMinimum: bool
     /// Показывать максимальные результаты.
     showMaximum: bool
     /// Количество итераций тестирования. Если указать значение
     /// 0, то количество итераций будет подобрано автоматически.
     iterationsCount: int
     /// Среднее время тестирование. Имеет смысл только при
     /// указании в качестве количества итераций значения 0.
     testTime: System.TimeSpan }

/// Настройки измерений по-умолчанию
val defaults: TestOptions

/// Измерение производительности кода
val run: (string * (unit -> unit)) list -> unit

/// Измерение производительности кода с заданными настройками
val runWithOptions:
    (string * (unit -> unit)) list -> TestOptions -> unit
{% endhighlight %}

А вот и реализация модуля, который делает всё то, что я описал выше (усыпанная комментариями и различными вкусностями языка F#):

{% highlight fsharp %}
module Measure

open System
open System.Threading
open System.Diagnostics

/// Настройки измерения производительности
[<NoEquality; NoComparison>]
type TestOptions =
   { perRunGC:      bool ; collectGCStat: bool
     highPriority:  bool ; checkTestEnv:  bool
     showProgress:  bool ; impactCorrect: bool
     warmIteration: bool ; clearConsole:  bool
     showAverage:   bool ; showMinimum:   bool
     showMaximum:   bool ; iterationsCount: int
     testTime:      TimeSpan }

/// Настройки измерений по-умолчанию
let defaults =
  { perRunGC      = true ; collectGCStat = true
    highPriority  = true ; checkTestEnv  = true
    showProgress  = true ; impactCorrect = false
    warmIteration = true ; clearConsole  = true
    showAverage   = true ; showMinimum   = false
    showMaximum  = false ; iterationsCount = 0
    testTime = TimeSpan.FromSeconds 3. }

/// Проверка среды тестирования
let checkEnvironment() =
    let fail reason =
        let message = "Ошибка проверки среды: " + reason
        in raise (InvalidOperationException message)

    // проверяем, подключен ли отладчик
    if Debugger.IsAttached then
       fail <| "тестирование следует производить "
             + "без подключенного отладчика."

    // проверяем, собрана ли сборка с оптимизациями
    let asm = Reflection.Assembly.GetExecutingAssembly()
    for attribute in asm.GetCustomAttributes false do
        match attribute with
        | :? DebuggableAttribute as d ->
          if d.IsJITOptimizerDisabled then
             fail "JIT-оптимизации не задействованы."
          if d.IsJITTrackingEnabled then
             fail "задействована JIT-трассировка."
        | _ -> ()

/// Результаты итерации тестирования
[<ReferenceEquality; NoComparison>]
type TestResult = { time: TimeSpan; gcStat: int[] }

type Console with
     static member Write(color, text) =
            Console.ForegroundColor <- color
            Console.Write(box text)

type con = Console
type color = ConsoleColor

/// Возвращает функцию-принтер
let precomputePrinter (names: string list) =
    // подсветка строк цветом
    let highl cond = if cond then color.Yellow
                             else color.DarkYellow
    // вычисляем один раз формат вывода имён и культуру
    let longestFrom = Seq.map String.length >> Seq.max
    let format = sprintf "{0,-%d}" (longestFrom names + 3)
    let culture = Globalization.CultureInfo.InvariantCulture

    fun (name: string) (count: int)
        (results: TestResult list) ->
      let initColor = con.ForegroundColor

      // заголовок таблицы результатов
      con.ForegroundColor <- color.DarkGray
      con.Write("{0} results ({1} iterations):\n",
                name, count)

      // наилучший результат по времени
      let bestTime = results |> Seq.minBy (fun x -> x.time)
      let bestGC = results // min кол-во сборок мусора
                |> Seq.map (fun x -> Array.sum x.gcStat)
                |> Seq.min

      // сравнение времени относительно наименьшего
      let bestTicks = float bestTime.time.Ticks
      let factors = List.map (fun result ->
          (float result.time.Ticks / bestTicks)
                       .ToString("F1", culture)) results
      let factorFmt = sprintf "{0,%d}x" (longestFrom factors)

      // печатаем табличку результатов
      for name, result, factor
          in Seq.zip3 names results factors do

          con.Write(color.DarkGray, "\n> ")
          con.ForegroundColor <- color.Gray
          con.Write(format, name) // имя теста

          // результат (выделяем минимальный)
          con.Write(color.DarkGray, " - ")
          con.ForegroundColor <- highl (result = bestTime)
          con.Write result.time

          // результат относительно наименьшего
          con.Write(color.DarkGray, " - ")
          con.ForegroundColor <- highl (result = bestTime)
          con.Write(factorFmt, factor)

          // статистика сборок мусора
          if result.gcStat <> Array.empty then
             con.Write(color.DarkGray, " - ")
             con.ForegroundColor <- highl
                 (Array.sum result.gcStat = bestGC)

             result.gcStat // не делайте так! :)
             |> Array.fold (fun tail count ->
                   if tail then con.Write '/'
                   con.Write count; true) false |> ignore

      con.ForegroundColor <- initColor
      con.WriteLine()
      con.WriteLine()

// заранее вычисляем строки чтобы минимизировать
// воздействие прогресс-бара на сборщик мусора
let blankLine = String(' ', con.BufferWidth - 1)
let progressLine = Array.init 100 (fun n -> String('.', n))

/// Очистка текущей строки
let clearLine() = con.CursorLeft <- 0
                  con.Write blankLine
                  con.CursorLeft <- 0

/// Показ прогресс-бара тестирования
let printProgress testid count =
    let initColor = con.ForegroundColor
    con.CursorVisible <- false
    con.CursorLeft <- 0

    if count = 0 then clearLine()

    con.Write(color.DarkGray, "test #")
    con.Write(testid: int)
    con.Write(" run")

    if count > 0 && count < 100 then
       con.Write(' ')
       con.Write(progressLine.[count])

    con.CursorVisible <- true
    con.ForegroundColor <- initColor

/// Показ сообщения о прерывании тестирования
let printCancelled() =
    let initColor = con.ForegroundColor
    con.ForegroundColor <- color.DarkRed
    con.WriteLine("test run stopped")
    con.ForegroundColor <- initColor

/// Запуск сборки мусора
let inline collectGC() = GC.Collect()
                         GC.WaitForPendingFinalizers()

/// Проверка нажатия клавиши Escape
let rec checkEscape () =
    if con.KeyAvailable
       then match con.ReadKey true with
            | с when с.Key = ConsoleKey.Escape -> true
            | _ -> checkEscape()
       else false

/// Вычисление средних результатов тестирования
let calcAvarage prevResults count =
  [ for results in prevResults ->
      { time = // вычисляем среднее время теста
            let sum = // складываем продолжительности
                results |> Seq.map (fun x -> x.time)
                        |> Seq.reduce (+)
            in TimeSpan.FromTicks( // делим на кол-во
                    sum.Ticks / int64 count)
        gcStat = // среднее кол-во сборок мусора
            // проверяем, собираем ли статистику GC
            match List.head results with
            | { gcStat = null } -> null
            | _ -> results // суммируем кол-во сборок
                |> Seq.map (fun x -> x.gcStat)
                |> Seq.reduce (Array.map2 (+))
                |> Array.map (fun x -> x / count) } ]

/// Вычисление максимальный или минимальных результатов
let calcExtr prevResults max =
  [ for results in prevResults ->
    { time = results |> Seq.map (fun x -> x.time)
                     |> if max then Seq.max else Seq.min
      gcStat = // макс или мин кол-во сборок мусора
        // проверяем, собираем ли статистику GC
        match List.head results with
        | { gcStat = null } -> null
        | _ -> results // ищем по сумме кол-ва сборок
            |> Seq.map (fun x -> x.gcStat)
            |> if max then Seq.maxBy Array.sum
                      else Seq.minBy Array.sum } ]

/// Измерение производительности
/// кода с заданными настройками
let runWithOptions
      (tests: (string * (unit -> unit)) list)
      (options: TestOptions) =

    if List.isEmpty tests then
       raise (ArgumentException "tests is empty.")

    // проверяем среду тестирования
    if options.checkTestEnv then checkEnvironment()

    // сохраняем приоритет текущего потока
    let thread = Thread.CurrentThread
    let initPriority = thread.Priority

    let printResults = // функция печати результатов
        precomputePrinter (List.map fst tests)
    let stopwatch = Stopwatch()
    let gcStat = // выделяем память под статистику GC
        if options.collectGCStat
           then Array.zeroCreate (GC.MaxGeneration + 1)
           else Array.empty

    // проведение одной итерации тестов
    let rec runTests id count tests results =
        match tests with
        | [] -> List.rev results  // по окончанию тестов
        | _ when checkEscape() -> printCancelled(); []
        | (_, test) :: left ->
          // вычисляем шаг строки прогресса
          let step = match count / 20 with 0 -> 1 | x -> x
          // запускаем прогревочную итерацию и GC
          if options.warmIteration then test() |> ignore
          if options.perRunGC then collectGC()
          stopwatch.Reset()

          // собираем информацию о сборках мусора
          if options.collectGCStat then
             for gen = 0 to gcStat.Length - 1 do
                 gcStat.[gen] <- GC.CollectionCount gen

          // выставляем приоритет потоку
          if options.highPriority then
             thread.Priority <- ThreadPriority.Highest

          stopwatch.Start() // само тестирование
          if options.showProgress
             then for i = 0 to count do
                      if i % step = 0 then
                         printProgress id (i / step)
                      test() |> ignore
             else for i = 0 to count do
                      test() |> ignore
          stopwatch.Stop()

          let gcStat = // собираем инф-цию о сборках мусора
              if options.collectGCStat then
                   Array.mapi (fun gen count ->
                     GC.CollectionCount gen - count) gcStat
              else Array.empty

          // подчищаем память после теста
          if options.perRunGC then collectGC()
          clearLine()

          { gcStat = gcStat // собираем результаты
            time = stopwatch.Elapsed } :: results
          |> runTests (id + 1) count left // и продолжаем

    // запуск тестов с корректировкой результатов
    let runWithCorrect count =
        // добавляем в начало списка пустой тест
        let tests = ("fake", fun() -> ()) :: tests
        match runTests 0 count tests [] with
        | [] -> [] // если тесты отменили
        | _ :: real as all ->
          // вычислем время самого быстрого теста
          let min = List.minBy (fun x -> x.time) all
          let delta = min.time - TimeSpan.FromTicks 1L
          con.WriteLine("delta = {0}", delta)

          // вычитаем это время из всех тестов
          let fix r = { r with time = r.time - delta }
          in List.map fix real

    // автоматическое вычисление количества итераций
    let rec calculateCount top count =
        match runTests 1 count tests [] with
        | []  ->  -1 // вызвана отмена тестирования
        | results -> // вычисляем суммарную длительность тестов
          let summary = results |> List.map (fun x -> x.time)
                                |> List.reduce (+)
          // процент достижения необходимой длительности
          let perc = float summary.Ticks
                   / float options.testTime.Ticks

          con.CursorTop <- top // переходим на первую строку
          con.Write( // строка всегда гарантированно длиннее
              "autotesting: {0:F2}% (iterations: {1})\n",
              perc * 100., count)

          if perc > 0.9 then
             con.CursorTop <- top; clearLine()
             con.WriteLine( // выводим конечное кол-во итераций
                "autotesting completed (iterations: {0})", count)
             count
          else // вычисляем прирост количества итераций
               let delta = int (float count * (1.0 - perc) * 2.)
               if delta = 0 then count * 2 else count + delta
               |> calculateCount top // повторно тестируем

    // повторные запуски тестов и усреднение результатов
    let rec runMany count prev =
        let results = // запускаем тесты с коррекцией или без
            if checkEscape() then printCancelled(); []
            elif options.impactCorrect
                 then runWithCorrect count
                 else runTests 1 count tests []
        match results, prev with
        | [], _ -> () // если тестирование остановили
        | results, [] -> // отображение результатов
           if options.clearConsole then con.Clear()
           printResults "Initial" count results
           runMany count [ for x in results -> [x] ]
        | results, (first :: _ as prev) ->
           if options.clearConsole then con.Clear()
           // соединяем результаты со списками предыдущих
           let prev = List.map2 (fun h t -> h::t) results prev
           // отображаем результаты теста
           printResults "Test" count results

           if options.showAverage then // средний результат
              // количество произведённых измерений
              let measureCount = List.length first + 1
              calcAvarage prev measureCount
              |> printResults "Average" count

           if options.showMinimum then // наименьший результат
              printResults "Minimum" count (calcExtr prev false)
           if options.showMaximum then // наибольший результат
              printResults "Minimum" count (calcExtr prev true)

           runMany count prev // продолжаем тестировать

    let count = // вычисляем количество итераций
        if options.iterationsCount > 0
           then options.iterationsCount
           else calculateCount con.CursorTop 1

    if count > 0 then
       runMany count [] // запускаем тестирование

       // возвращаем потоку изначальный приоритет
       if options.highPriority then
          thread.Priority <- initPriority

/// Измерение производительности кода
let run tests = runWithOptions tests defaults
{% endhighlight %}

Пример вывода результатов:

![](http://media.tumblr.com/tumblr_lg5biq50ie1qdrm28.png)

Замечания к реализации:

* Модуль содержит всего две функции: `run` и `runWithOptions`. Первая из них пользуется настройками по умолчанию, вторая позволяет задать необходимые настройки в виде значения типа `TestOptions`. Обе функции получают тестируемые фрагменты кода в виде списка кортежей из строкового имени теста и функции типа `(unit -> unit)`.
* При задании настроек совсем не обязательно создавать экземпляр `TestOptions` инициализируя все поля record’а. Можно воспользоваться копирующим `with`-выражением F# и значением `defaults`, определённым в модуле для того, чтобы изменить настройки частично, например: `{ Measure.defaults with checkTestEnv = false }`.
* Отмена тестирования - клавиша `Escape`, работает с интервалом в один тест и предпочитает показать результаты, если это возможно.
* Показ прогресса написан так, чтобы не выделять память на куче, однако инфраструктура `System.Console` внутри всё равно производит некоторые выделения памяти, поэтому от некоторого влияния можно избавиться только отключив показ прогресса.
* Данная реализация отображает отношение каждого из тестов по времени к самому быстрому (затратившего минимальное время).
* Не вздумайте запускать в F# Interactive, только обычным exe-приложением вне VisualStudio.

Выводит результаты он достаточно симпатично, например, протестируем скорость работы функции `Printf.sprintf` из состава стандартной бибилиотеки F# по сравнению с конкатенацией строк и методом `System.String.Format`:

{% highlight fsharp %}
// пропущенные через `id` значения
// не заинлайнятся далее по коду
let name = id "Alex"
let age  = id 22

// Тестируем сбор строки вида:
//  "My name is Alex (22 years old)"

Measure.runWithOptions [
   // через сложение строк
   "System.String.Concat", fun()->
      "My name is " + name +
               " (" + string age + " years old)"
      |> ignore

   // через метод string.Format
   "System.String.Format", fun() ->
      System.String.Format(
         "My name is {0} ({1} years old)", name, age)
      |> ignore

   // через метод Printf.sprintf
   "Printf.sprintf", fun() ->
      Printf.sprintf
           "My name is %s (%d years old)" name age
      |> ignore

    // и дополнительно отображаем мин/макс время
  ] { Measure.defaults with showMinimum = true
                            showMaximum = true }
{% endhighlight %}

Получаем следующий результат (на машине старенький Athlon 64 X2 @2.4GHz):

![](http://media.tumblr.com/tumblr_lg5dm2ebwB1qdrm28.png)

Ужасно, правда? В чём же причина тормознутости функции `sprintf`?

Оказывается, что большинство пользователей F# используют данную и другие функции из модуля `Printf` не совсем корректно. Всё семейство `printf`-функций из данного модуля на самом деле осуществляют разбор строки формата и динамически формируют функцию (часто с аргументами в каррированной форме, как в примере выше: `string -> int -> unit`). Функция возвращается пользователю и последующее применение всех аргументов вызывают печать в консоль/строку/`TextWriter`, смотря какой из функций модуля `Printf` вы пользуетесь. Существенное время тратится на формирование данной функции и этого можно избежать, если заранее вычислить эту функцию и сохранить в какой-нибудь `let`-привязке. Перепишем тест следующим образом и проверим результатом:

{% highlight fsharp %}
let name = id "Alex"
let age  = id 22

let k = Printf.sprintf "My name is %s (%d years old)"

Measure.runWithOptions [
   // через метод Printf.sprintf
   "Printf.sprintf", fun() ->
      Printf.sprintf
           "My name is %s (%d years old)" name age
      |> ignore

   // через заранее сформированную функцию
   "k = Printf.sprintf", fun() ->
      k name age |> ignore

  ] { Measure.defaults with showMinimum = true
                            showMaximum = true }
{% endhighlight %}

В итоге обнаруживаем, что время сокращается вдвое, а нагрузка на GC примерно на треть:

![](http://media.tumblr.com/tumblr_lg5e66cs361qdrm28.png)

Однако даже при этом функция `sprintf` оказывается более, чем *на порядок* медленне метода `String.Format` и просто нещадно мусорит на куче, что должно заставить задуматься о целесообразности применения (или хотя бы о более оптимальном применении засчёт предварительного формирования функции печати) модуля `Printf` в узких местах приложения. И это далеко не единственное место, где F# просто ужасно тормозит ;)

Как говорится, feel free to contribute!