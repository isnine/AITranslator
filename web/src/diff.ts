type Op = "equal" | "insert" | "delete";

interface Segment {
  op: Op;
  text: string;
}

function tokenize(s: string): string[] {
  return s.match(/\s+|[^\s]+/g) ?? [];
}

export function wordDiff(oldText: string, newText: string): Segment[] {
  const a = tokenize(oldText);
  const b = tokenize(newText);
  const n = a.length;
  const m = b.length;
  const dp: number[][] = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));

  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      dp[i][j] =
        a[i - 1] === b[j - 1] ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1]);
    }
  }

  const segs: Segment[] = [];
  let i = n;
  let j = m;
  while (i > 0 && j > 0) {
    if (a[i - 1] === b[j - 1]) {
      segs.push({ op: "equal", text: a[i - 1] });
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      segs.push({ op: "delete", text: a[i - 1] });
      i--;
    } else {
      segs.push({ op: "insert", text: b[j - 1] });
      j--;
    }
  }
  while (i > 0) {
    segs.push({ op: "delete", text: a[i - 1] });
    i--;
  }
  while (j > 0) {
    segs.push({ op: "insert", text: b[j - 1] });
    j--;
  }
  return segs.reverse();
}
