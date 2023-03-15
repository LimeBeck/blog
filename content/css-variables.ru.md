+++
title = "Переопределение цвета переменными CSS с указанием цвета по умолчанию"
date = 2023-03-15
[taxonomies]
tags = ["til", "css", "styles"]
+++

### TL;DR;

* Задаём дефолтные значения (`defaults.css`)
    ```css
    ::root {
        --primary: red;
    }
    ```

* Задаём стили компонента (`styles.css`)
    ```css
    body {
        color: blue;
        font-size: 40px;
        --default-primary: yellow;
        color: var(--primary,var(--default-primary))
    }
    ```

* Оверрайдим в рантайме (`overrides.css`)
    ```css
    ::root {
        --primary: blue;
    }
    ```
    или с использованием JS
    ```js
    document.querySelector(':root').style.setProperty('--primary', 'blue')
    ```
<!-- more -->
