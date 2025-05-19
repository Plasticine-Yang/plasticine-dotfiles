# 1. 安装 oh-my-zsh

官网推荐的安装方式

```shell
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

直接使用官网的方式安装`oh-my-zsh`会遇到下面的问题

![image.png](https://cdn.nlark.com/yuque/0/2022/png/25507190/1655165161786-66ad8560-02f8-409a-896b-df8aeb93ec72.png#clientId=u4199c115-bb6e-4&crop=0&crop=0&crop=1&crop=1&from=paste&height=33&id=u2678f067&margin=%5Bobject%20Object%5D&name=image.png&originHeight=46&originWidth=1375&originalType=binary&ratio=1&rotation=0&showTitle=false&size=80476&status=done&style=none&taskId=ua2a8dc49-e815-4558-91bc-6a47af6ea59&title=&width=1000)

这是因为`linux`没有翻墙导致的，要么挂代理翻墙，要么在能翻墙的主机上将`curl`的这个脚本下载下来，然后再传给`linux`执行这个脚本即可

也可以使用`github`代理网站进行处理，加上`https://ghproxy.com`前缀即可

```shell
sh -c "$(curl -fsSL https://ghproxy.com/https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

## 1.1 WSL2 挂代理

如果你和我一样使用的是`WSL2`的话，可以使用下面这种方式使用`windows`的代理

### 1. 获取 windows DNS 地址

`WSL2`会使用`windows`的网关作为`DNS`服务器的地址，设置代理的思路就是通过网关访问到`windwos`，然后将代理设置为`windows`网关上的代理软件的端口即可
通过下面这个命令可以获取到`linux`的`DNS`服务器地址

```shell
cat /etc/resolv.conf
```

---

### 2. 设置 linux 代理

`linux`的系统代理是通过一个环境变量 -- `ALL_PROXY`来配置的，上面我们已经拿到了`windows`的网关`ip`，那么接下来只需要设置一个以该`ip`为主机名，再拼接上代理软件开放的端口的`ALL_PROXY`环境变量即可

```shell
export ALL_PROXY=http://ip_addr:proxy_port
```

---

### 3. 编写成脚本

可以将上述过程用脚本描述出来

```shell
#!/bin/bash

hostIp=$(cat /etc/resolv.conf | grep "nameserver" | cut -f 2 -d " ")
export ALL_PROXY="http://$hostIp:10809"
```

关闭代理也很简单，将`ALL_PROXY`环境变量删除即可，也可以编写成一个脚本

```shell
#!/bin/bash

unset ALL_PROXY
```

---

### 4. 将脚本放到方便的地方让所有用户可以使用

将上述脚本放到`/etc/proxy-utils`目录下，要开启代理就执行：

```shell
source /etc/proxy-utils/start-proxy
```

要关闭代理则执行

```shell
source /etc/proxy-utils/stop-proxy
```

非常的方便！

---

# 2. 主题

安装完`oh-my-zsh`后就会在用户目录下生成一个`.oh-my-zsh`的目录，里面的`themes`目录就是当前已安装的主题
![image.png](https://cdn.nlark.com/yuque/0/2022/png/25507190/1655190974544-ae0057f0-595e-4f31-8b46-6fd09a479644.png#clientId=uc8df632a-8c51-4&crop=0&crop=0&crop=1&crop=1&from=paste&height=572&id=u87847280&margin=%5Bobject%20Object%5D&name=image.png&originHeight=786&originWidth=1887&originalType=binary&ratio=1&rotation=0&showTitle=false&size=147565&status=done&style=none&taskId=uaa33de65-1ef5-44ba-b69f-33b6ee04d5e&title=&width=1372.3636363636363)
这么多主题却不知道它们都长啥样对吧？一个个应用后再查看又太麻烦，可以到[官网主题展示](https://github.com/ohmyzsh/ohmyzsh/wiki/Themes)查看每款主题的效果，总有一款深得你心~
可以直接编辑用户目录下的`.zshrc`，配置`ZSH_THEME`配置项为想用的主题名，然后`source ~/.zshrc`即可让主题生效
如果上面这些自带主题你都不喜欢的话，还有[更多主题](https://github.com/ohmyzsh/ohmyzsh/wiki/External-themes)可以使用，但是由于这些是第三方主题，所以需要额外安装使用，每款主题都会说明安装方式的，自行查看即可

---

# 3. 插件

`zsh`有各种各样丰富的插件，能够极大程度上提高我们的终端体验！
在`.zshrc`中的`plugins`配置插件数组即可让插件生效
用`()`包裹的就是数组，数组中每一个元素通过空白符分隔（如空格、`tab`、换行符）

## 3.1 vi-mode

这个插件能够让你的`zsh`使用起来就像在用`vim`一样，拥有大部分`vim`的特性，比如：

- 默认是`insert`模式，可以按下`esc`或`ctrl [`进入`normal`模式，使用`h`进行左移，`l`进行右移，使用`k`回到上一条命令，`j`回到下一条命令
- 任何模式下`ctrl p`可以查看上一条命令
- 任何模式下`ctrl n`可以查看下一条命令
- `/`搜索历史命令
- 在`normal`模式下输入`vv`可以进入`vim`编写当前输入的命令

其他的移动删除等操作就和`vim`一致了，安装该插件很简单，在`.zshrc`的`plugins`数组中配置即可

### 光标随模式切换

刚安装完`vi-mode`的时候你会发现，无论进入什么模式，光标都是一个方块，不一会儿就会容易忘记自己当前是在哪个模式里（虽然可以配置命令行输入处的右边的提示符来判断，但是我个人觉得用处不大，很少会往右边看）
如果能够在`normal`模式下是方块光标，而`insert`模式下变成我们都习惯的竖线光标的话，就可以完美解决这个问题了，那么这一点能否办到呢？
肯定可以啦！只需要在`.zshrc`中配置如下选项

```shell
VI_MODE_RESET_PROMPT_ON_MODE_CHANGE=true
VI_MODE_SET_CURSOR=true
```

这样就会在`normal`模式下以方格显示光标，而`insert`模式下以竖线显示光标，能够让我们很直观地直到自己当前处于什么模式下
![光标随模式切换.gif](https://cdn.nlark.com/yuque/0/2022/gif/25507190/1655178089887-57f9b5cb-0347-4601-993a-ed6ed40e83c2.gif#clientId=u9f903c3e-8d4d-4&crop=0&crop=0&crop=1&crop=1&from=ui&id=u891b885a&margin=%5Bobject%20Object%5D&name=%E5%85%89%E6%A0%87%E9%9A%8F%E6%A8%A1%E5%BC%8F%E5%88%87%E6%8D%A2.gif&originHeight=791&originWidth=1120&originalType=binary&ratio=1&rotation=0&showTitle=false&size=43659&status=done&style=none&taskId=u53dbad59-6860-4170-bce2-a10959d73f8&title=)

### 按键映射 jk 回到 normal 模式

由于`jk`连续字符一般用不上，而且又很方便我们的手指按到，所以可以将`jk`映射成回到`normal`模式，修改`.zshrc`，添加如下配置

```shell
bindkey -M viins 'jk' vi-cmd-mode
KEYTIMEOUT=25
```

如果不设置`KEYTIMEOUT`，使用的时候会明显感觉到按下`jk`后会延迟一段时间才进入`normal`模式，将延迟设置为`25`即可解决

---

## 3.2 z - jump around

这个命令可以记录你的历史访问目录，当你需要跳转回历史访问过的目录的时候，直接输入`z [目录名]`即可，目录名不需要完整填写，可以是一部分，就像下面这样：
![image.png](https://cdn.nlark.com/yuque/0/2022/png/25507190/1655172636289-2612e84c-9820-402a-a952-37232dc6cae8.png#clientId=u9f903c3e-8d4d-4&crop=0&crop=0&crop=1&crop=1&from=paste&height=148&id=u9c994494&margin=%5Bobject%20Object%5D&name=image.png&originHeight=204&originWidth=1883&originalType=binary&ratio=1&rotation=0&showTitle=false&size=22735&status=done&style=none&taskId=uec7ad735-8299-4c0f-b469-9938a15c1ae&title=&width=1369.4545454545455)

---

## 3.3 **history-substring-search**

该插件能够记录你的历史命令，当你输入历史命令的前缀时，按下上下方向键可以匹配当前输入的命令为前缀的历史命令
该插件的安装方式不同于前面介绍的插件，直接在`plugins`数组中配置是不行的
因为它是一个`custom plugin`，需要被放到`.oh-my-zsh`目录的`custom/plugins`目录中
所以我们需要先将它的源码克隆到`~/.oh-my-zsh/custom/plugins`目录，然后再配置`history-substring-search`到`.zshrc`的`plugins`数组中即可

```shell
 git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
```

### 按键映射与 vi-mode 体验统一

默认情况下是使用上下方向键翻看历史记录，这样太不方便了，所以我们可以修改一下按键映射，让它和之前配置的`vi-mode`插件的使用体验统一

- 将`k`映射到`history-substring-search-up`，触发该插件的上翻历史记录
- 将`j`映射到`history-substring-search-down`，触发该插件的下翻历史记录

```shell
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down
```

---

## 3.4 autosuggestions

> It suggests commands as you type based on history and completions.

能够基于历史命令给你提示补全信息，由于也是一个`custom plugin`，所以需要额外将其源码克隆到`.oh-my-zsh/custom/plugins`目录下才能配置生效

```shell
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
```

然后到`.zshrc`的`plugins`数组中加上`zsh-autosuggestions`即可
![image.png](https://cdn.nlark.com/yuque/0/2022/png/25507190/1655176608611-4e879c25-e24e-4042-a15d-6f4b05ea4f9a.png#clientId=u9f903c3e-8d4d-4&crop=0&crop=0&crop=1&crop=1&from=paste&height=44&id=u0d1b41a3&margin=%5Bobject%20Object%5D&name=image.png&originHeight=60&originWidth=219&originalType=binary&ratio=1&rotation=0&showTitle=false&size=2427&status=done&style=none&taskId=ua9db6a1a-ea1e-438a-a56e-8ae46e967c6&title=&width=159.27272727272728)
可以看到效果就像这样，此时按下右方向键即可补全，但是按下右方向键右手需要移动一段距离，不太方便，可以映射成`ctrl space`来完成补全
修改`.zshrc`

```shell
bindkey '^ ' autosuggest-accept
```

---

## 3.5 zsh-syntax-highlighting

这个插件能够让你在执行命令之前就直到当前命令是否有可能报错，比如命令不存在时，输入完该命令还没按下回车就会看到它是红色高亮显示的，而如果命令存在则会以绿色高亮显示
同样，它也是一个`custom plugin`，所以老套路了

```shell
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

然后将`zsh-syntax-highlighting`添加到`plugins`数组中即可
![image.png](https://cdn.nlark.com/yuque/0/2022/png/25507190/1655177894156-3abb81a2-fc06-4962-9ef8-b877a40b794e.png#clientId=u9f903c3e-8d4d-4&crop=0&crop=0&crop=1&crop=1&from=paste&height=55&id=ub086ff12&margin=%5Bobject%20Object%5D&name=image.png&originHeight=76&originWidth=210&originalType=binary&ratio=1&rotation=0&showTitle=false&size=2444&status=done&style=none&taskId=u753992c0-bee0-4aa1-b5ef-31d4b1e4b15&title=&width=152.72727272727272)
可以看到现在有高亮提示了

---

## 3.6 dirhistory

从名字就可以看出来，这个插件能够记录我们的访问目录历史，它最多能够保留`30`条历史记录
当需要查看访问目录历史的时候，输入`dirs -v`或者`d`即可
![image.png](https://cdn.nlark.com/yuque/0/2022/png/25507190/1655176029033-9a57bf9e-c1a3-4786-99d6-206453b89ab0.png#clientId=u9f903c3e-8d4d-4&crop=0&crop=0&crop=1&crop=1&from=paste&height=159&id=uf92e7ead&margin=%5Bobject%20Object%5D&name=image.png&originHeight=219&originWidth=286&originalType=binary&ratio=1&rotation=0&showTitle=false&size=8196&status=done&style=none&taskId=u84c4511a-a052-4773-ad5e-946181277dd&title=&width=208)
我首先进入了`~`家目录，又切换到了`/usr`，然后进入到`/usr/share`最后进入到`/usr/share/doc`
这时候按下`d`就可以看到它记录过的目录历史
当前我所在目录是`/usr/share/doc`，按下`alt ←`会让我回到上一条目录历史，也就是`/usr/share`，再按下`alt ←`会回到`/usr`依此类推
同理，当前我回到了`/usr`，那么按下`alt →`会回到`/usr/share`，再按下会回到`/usr/share/doc`
当前我在`/usr/share/doc`，按下`alt ↑`会进入到当前所在目录的父目录，也就是`/usr/share`
当前我在`/usr/share`，按下`alt ↓`会进入到当前目录的第一个子目录，由于我的系统的`/usr/share`的第一个子目录是`GConf`，所以按下后我会进入到`/usr/share/GConf`
**这意味着无论你在什么目录下，你都可以扔掉**`**cd ..**`**的方式回到上一级目录了，直接**`**alt ↑**`**就可以搞定！**

---

# 4. 和 root 用户共享 zsh 配置

当你花了老半天配置了半天的主题和各种插件后，突然有一天不得不进入到`root`用户中进行一些操作的时候，却发现进来之后，一切都是最原始的一样子，是那么的难用，那么的不习惯的时候，那得多么崩溃
因为之前配置的东西全都是在别的用户中配置的，只会对当时配置的用户生效，当你切换用户的时候，就需要重新配置了
那肯定不乐意了，折腾了老半天又要我重新折腾这不搞笑呢嘛，别急，可以通过软链接（符号链接）的方式解决这个问题
通过软链接的方式，将当前用户的`.zshrc`和`.oh-my-zsh`软链接到`root`用户的家目录中

```shell
ln -s $HOME/.zshrc /root/.zshrc
ln -s $HOME/.oh-my-zsh /root/.oh-my-zsh
```

还需要在`.zshrc`开头写入

```shell
ZSH_DISABLE_COMPFIX="true"
```

这个配置项能够跳过安全检查，否则在`root`用户下会出现安全警告，如果担心这个安全警告会对你的系统造成什么影响的话那就老老实实重新配置一遍，或者直接把原来配置好的用户家目录下的`.zshrc`和`.oh-my-zsh`赋值到`root`用户中
