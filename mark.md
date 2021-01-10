# 博客记录

## hexo的使用

写作指南操作：

1. hexo new [layout] <title>
    + layout 列表
    + post 存储在`source/_posts`
    + page 存储在`source`
    + draft 存储在`source/_drafts`
    + 名称可以采用`:year-:month-:day-:title.md`来管理温行
2. hexo pulish <title> 对草稿进行操作，将草稿的内容push到`_post`里面
3. post的tag
   1. title是整体的现实名称
   2. tags: 是标签，类似于yaml格式，是一个list，使用`[]`或者`- tag`进行标记。
   3. index_image: 是标题的图片，在主页。
   4. banner_img:  是post文章中的top图。
   5. date: YYYY-MM-DD HH:MM:SS
   6. comment: true，是否开启标题
   7. 文章中的`标签`
    ```js
    {% note success %}
    文字 或者 `markdown` 均可
    {% endnote %}
    ```
   8. todo 勾选 {% cb text, checked?, incline? %}
   9. 按钮 {% btn url, text, title %}

hexo的基础操作
1. `hexo g`：构建
2. `hexo c`：清空原来的tag
3. `hexo d`：部署
