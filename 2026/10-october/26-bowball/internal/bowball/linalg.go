package bowball

import (
	"errors"
	"math"
)

// matrix is a dense square or rectangular matrix, row by row.
type matrix [][]float64

func newMatrix(rows, cols int) matrix {
	m := make(matrix, rows)
	for i := range m {
		m[i] = make([]float64, cols)
	}
	return m
}

var errSingular = errors.New("matrix is singular")

// invert returns the inverse of a symmetric positive-definite matrix by Gauss-Jordan
// elimination with partial pivoting. The input is not changed.
func invert(a matrix) (matrix, error) {
	n := len(a)
	work := newMatrix(n, 2*n)
	for i := 0; i < n; i++ {
		copy(work[i], a[i])
		work[i][n+i] = 1
	}
	for col := 0; col < n; col++ {
		pivot := col
		for r := col + 1; r < n; r++ {
			if math.Abs(work[r][col]) > math.Abs(work[pivot][col]) {
				pivot = r
			}
		}
		if math.Abs(work[pivot][col]) < 1e-12 {
			return nil, errSingular
		}
		work[col], work[pivot] = work[pivot], work[col]
		p := work[col][col]
		for k := range work[col] {
			work[col][k] /= p
		}
		for r := 0; r < n; r++ {
			if r == col || work[r][col] == 0 {
				continue
			}
			f := work[r][col]
			for k := range work[r] {
				work[r][k] -= f * work[col][k]
			}
		}
	}
	inv := newMatrix(n, n)
	for i := 0; i < n; i++ {
		copy(inv[i], work[i][n:])
	}
	return inv, nil
}

// cholesky returns lower-triangular L with L Lᵀ = a, for a symmetric positive-definite matrix.
func cholesky(a matrix) (matrix, error) {
	n := len(a)
	l := newMatrix(n, n)
	for i := 0; i < n; i++ {
		for j := 0; j <= i; j++ {
			sum := a[i][j]
			for k := 0; k < j; k++ {
				sum -= l[i][k] * l[j][k]
			}
			if i == j {
				if sum <= 0 {
					return nil, errSingular
				}
				l[i][i] = math.Sqrt(sum)
			} else {
				l[i][j] = sum / l[j][j]
			}
		}
	}
	return l, nil
}

// quad returns cᵀ a c.
func quad(a matrix, c []float64) float64 {
	total := 0.0
	for i, ci := range c {
		if ci == 0 {
			continue
		}
		for j, cj := range c {
			total += ci * a[i][j] * cj
		}
	}
	return total
}

// mulVec returns a v.
func mulVec(a matrix, v []float64) []float64 {
	out := make([]float64, len(a))
	for i, row := range a {
		for j, x := range row {
			out[i] += x * v[j]
		}
	}
	return out
}

// normalCDF is the standard normal cumulative distribution function.
func normalCDF(z float64) float64 { return 0.5 * math.Erfc(-z/math.Sqrt2) }
