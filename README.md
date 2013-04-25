# summary

musasaua is a [http](http://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol)/[https](http://en.wikipedia.org/wiki/HTTP_Secure) library with built in support for [proxy](http://en.wikipedia.org/wiki/Tunneling_protocol), [cookies](http://en.wikipedia.org/wiki/HTTP_cookie) and [redirect](http://en.wikipedia.org/wiki/URL_redirection), written in pure [Lua](http://www.lua.org/) on top of [Luvit](http://luvit.io/).

# WTF musasaua means?

musasaua means "force passage" in [nheengatu](http://en.wikipedia.org/wiki/Nheengatu_language)

# help and support

please fill an issue or help it doing a clone and then a pull request

# license

[BEER-WARE](http://en.wikipedia.org/wiki/Beerware), see source
  
# basic usage

```lua
    
    musasaua              = require 'musasaua'
    musasaua.enable_debug = true  -- debug
    musasaua.read_timeout = 20000 -- in mileseconds
    musasaua:request(
      {
        url    = 'http://example.com/index.html', -- request example.com using proxy e.g. tor/polipo
        method = 'CONNECT', 
        domain = '127.0.0.1', 
        port   = 8123
      },  
      function(data)
        if data and data.code==200 then
          print(data.body)
        end
      end
    )

```

# test

... in progress

# TODO

+ support luvit module style
+ create a test suite
+ create a wiki?

% April 25th, 2013 -03 GMT