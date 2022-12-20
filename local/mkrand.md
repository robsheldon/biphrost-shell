# Generate a random string

**Examples:**
```
$ biphrost mkrand 'a-f0-9' 20
```

**Check arguments**
```bash
shift
if [ $# -lt 2 ]; then
    fail "Usage: mkrand [pattern] [count]"
fi
if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
    fail "Count must be an integer"
fi
```

**Output**
```bash
tr -dc "$1" < /dev/urandom | head -c "$2"
```