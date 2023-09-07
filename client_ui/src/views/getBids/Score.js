function calculateScore(upvotes, downvotes) {
  const n = upvotes + downvotes

  if (n === 0) {
    return 0
  }

  //z-score for 95% two-sided confidence = 1.96
  const z = 1.96
  const p = upvotes / n
  const left = p + (1 / (2 * n)) * z * z
  const right = z * Math.sqrt((p * (1 - p)) / n + (z * z) / (4 * n * n))
  const under = 1 + (1 / n) * z * z
  const score = (left - right) / under
  return score
}

export default calculateScore
