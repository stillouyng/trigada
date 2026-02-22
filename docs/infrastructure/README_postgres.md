# PostgreSQL

<p align="right">
  <a href="README_postgres.ru.md">RU</a>
  <span>|</span>
  <b>EN</b>
</p>

**Version:** 18.2

The database starts with initialization scripts. These scripts are executed **only if the volume does not already exist**.  
This technically means that all extensions, schemas, functions, and triggers are initialized **only during the very first build** and will NOT run again unless the volume is removed.



### 0. [Initialization Script](../../infrastructure/postgres/init/00-init.sql)

 - `Maintenance` schema for all custom functions.


### 1. [Additional Extenstions](../../infrastructure/postgres/init/01-extensions.sql)

 - `HypoPG`. An additional extenstion that allows testing hypotetical indexes before physically creating them. (Not included in the base 18.2 postgres image, installed via the[`Dockerfile`](../../infrastructure/postgres/Dockerfile))


 ### 2. [Functions](../../infrastructure/postgres/init/02-functions.sql)

 - `find_useless_indexes`. This function analyzes:
   - how many times an index was scanned
   - how many rows it processed
   - how much data it touched
   
   and returns a basic recommendation.
   
   **WARNING:**  
   Do not rely solely on this function.  
   It is not fully comprehensive and may produce inaccurate recommendations in some cases.

 - `find_duplicates_indexes`. Detects duplicate indexes.   

  | Method | Implementation |
  |--------|----------------|
  | Exact duplicates | ✅ Implemented |
  | Left-side duplicates | ❌ Not implemented |
  | Partial comparison | ❌❌❌ And remember... No partial checks |


### 3. [Triggers](../../infrastructure/postgres/init/03-triggers.sql)

**Not implemented yet**

> Reserved for future triggers.  
> All triggers will include proper documentation and follow a consistent structure.  
> Consistency is key.