if [ $1 = -i ]
then
    mkdir output
    git clone -b gh-pages git@github.com:daysneco/wiki.git output
    exit 0
elif [ $1 =  ]
then
#    echo deploy [Option]
#    echo        -i 初始化
#    echo        message  提交到github并发布，提交信息为mesage
#    exit 0
    git pull origin master
    cd output
    git pull origin gh-pages
    cd ..
    exit 0
else
    git add . --all
    git commit -am $1
    git pull origin master
    git push origin master

    simiki g
    cd output
    mkdir src
    git add . --all
    git commit -am $1
    git pull origin gh-pages
    git push origin gh-pages
    cd ..
    
fi
