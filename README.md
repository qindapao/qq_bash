
# qq_bash

A personal bash library

## Run tests

Enter the root directory of the project and directly execute the `test.sh` script.

## Define the variables within a function that need to be passed to a sub-function for processing.

Since subfunctions require the use of `local -n` references to variables, a naming convention—designed to avoid name collisions—involves prefixing these variables with the current function name (formatted in PascalCase). For example:

```bash
test_func1 ()
{
	local TestFunc1_var1=
	test_func2 TestFunc1_var1
	echo "long1: $TestFunc1_var1"
	local -n short=TestFunc1_var1
	echo "short1: $short"
}

test_func2 ()
{
	local -n get_var=$1
	get_var="a tring 2"
	local TestFunc2_var1=
	test_func3 TestFunc2_var1
	echo "long2: $TestFunc2_var1"
}

test_func3 ()
{
	local -n get_var=$1
	get_var="a tring 3"
}

test_func1
```

Other types of variables within a function are not subject to this constraint and may use very short, lowercase names.

## API

TODO


