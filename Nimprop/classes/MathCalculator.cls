public class MathCalculator {

    private static Integer add(Integer a, Integer b) {
        return a + b;
    }

    private static Integer multiply(Integer a, Integer b) {
        return a * b;
    }

    private static void printOutput(Integer result) {
        System.debug(result);
    }

    public void doMath() {
        Integer sum = add(10, 20);
        Integer product = multiply(10, 20);

        printOutput(sum);
        printOutput(product);
    }
}