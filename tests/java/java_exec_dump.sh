path=$(dirname $0)

cd "$path/$1"
for i in `ls *.class 2>/dev/null`
do
    name=$(echo "$i" | cut -f 1 -d '.')
    if ! [[ $name == *'$'* ]]; then
	java $name > out/$name
    fi
done
