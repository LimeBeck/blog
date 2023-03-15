+++
title = "CSS runtime colors changing"
date = 2023-03-15
[taxonomies]
tags = ["til", "css", "styles"]
+++

### TL;DR;

* Set default values (`defaults.css`)
    ```css
    ::root {
        --primary: red;
    }
    ```

* Using it in components styles (`styles.css`)
    ```css
    body {
        color: blue;
        font-size: 40px;
        --default-primary: yellow;
        color: var(--primary,var(--default-primary))
    }
    ```

* Override in runtime (`overrides.css`)
    ```css
    ::root {
        --primary: blue;
    }
    ```
    or using JS
    ```js
    document.querySelector(':root').style.setProperty('--primary', 'blue')
    ```

<!-- more -->
