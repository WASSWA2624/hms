/**
 * Phase 2 Prisma foundation verification tests.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const readProjectFile = (relativePath) =>
  fs.readFileSync(path.join(process.cwd(), relativePath), 'utf8');

describe('phase 2 prisma foundation contracts', () => {
  it('keeps datasource URL out of schema.prisma for Prisma 7 adapter mode', () => {
    const schema = readProjectFile('prisma/schema.prisma');
    const datasourceBlock = schema.match(/datasource\s+db\s*\{[\s\S]*?\}/);

    expect(schema).toMatch(/generator\s+client\s*\{/);
    expect(datasourceBlock).not.toBeNull();
    expect(datasourceBlock[0]).not.toMatch(/\burl\s*=/);
  });

  it('loads Prisma CLI datasource URL through src/config/env.js only', () => {
    const prismaConfig = readProjectFile('prisma.config.js');

    expect(prismaConfig).toMatch(/require\(['"]\.\/src\/config\/env['"]\)/);
    expect(prismaConfig).not.toMatch(/process\.env/);
  });

  it('keeps prisma client wrapper aligned to the MariaDB adapter without direct process.env', () => {
    const prismaClient = readProjectFile('src/prisma/client.js');

    expect(prismaClient).toMatch(/@prisma\/adapter-mariadb/);
    expect(prismaClient).toMatch(/PrismaMariaDb/);
    expect(prismaClient).toMatch(
      /searchParams\.set\(\s*'allowPublicKeyRetrieval'[\s\S]*PRISMA_MYSQL_ALLOW_PUBLIC_KEY_RETRIEVAL/
    );
    expect(prismaClient).not.toMatch(/process\.env/);
  });

  it('can require src/prisma/client.js without pre-registering aliases', () => {
    const bootstrapScript = `
process.env.DATABASE_URL = 'mysql://demo:demo@127.0.0.1:3306/hms_db';
process.env.JWT_SECRET = '12345678901234567890123456789012';
process.env.CORS_ORIGINS = 'http://localhost:8081';
process.env.NODE_ENV = 'test';
process.env.DOTENV_QUIET = 'true';
const prisma = require('./src/prisma/client');
if (!prisma || typeof prisma.$disconnect !== 'function') {
  throw new Error('Invalid Prisma client export');
}
console.log('ok');
`;

    const output = execFileSync(process.execPath, ['-e', bootstrapScript], {
      cwd: process.cwd(),
      encoding: 'utf8',
      timeout: 8000});

    expect(output).toContain('ok');
  });

  it('keeps readiness Prisma timeout at 2 seconds for fast failure', () => {
    const readinessSource = readProjectFile('src/lib/health/readinessCheck.js');
    expect(readinessSource).toMatch(/const PRISMA_TIMEOUT_MS = 2000;/);
  });

  it('skips friendly-id assignment on models without human_friendly_id', () => {
    const prismaClient = readProjectFile('src/prisma/client.js');
    const schema = readProjectFile('prisma/schema.prisma');
    const itemBlock = schema.match(
      /model\s+patient_deletion_batch_item\s*\{[\s\S]*?\n\}/
    );

    expect(itemBlock).not.toBeNull();
    expect(itemBlock[0]).not.toMatch(/\bhuman_friendly_id\b/);
    expect(prismaClient).toMatch(/modelHasHumanFriendlyId\(model\)/);
    expect(prismaClient).toMatch(/if \(!modelHasHumanFriendlyId\(model\)\) return;/);
  });
});

