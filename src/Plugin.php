<?php

declare(strict_types=1);

namespace Vondry\BoltSkills;

use Composer\Composer;
use Composer\EventDispatcher\EventSubscriberInterface;
use Composer\IO\IOInterface;
use Composer\Plugin\PluginInterface;
use Composer\Script\ScriptEvents;
use Composer\Util\Filesystem;
use Composer\Util\Platform;

/**
 * Exposes the bundled skills to AI agents in the consuming project.
 *
 * On `composer install` / `composer update` every skill is symlinked into the
 * agent skill directories (default `.claude/skills/` and `.agents/skills/`),
 * and managed blocks are written to `.gitignore` and `AGENTS.md`.
 * On `composer remove` everything the plugin created is removed again.
 *
 * Optional configuration in the project's composer.json:
 *
 *     "extra": {
 *         "bolt-skills": {
 *             "targets": [".claude/skills", ".agents/skills"],
 *             "agents-md": true,
 *             "gitignore": true
 *         }
 *     }
 */
final class Plugin implements PluginInterface, EventSubscriberInterface
{
    public const PACKAGE_NAME = 'vondry/bolt-skills';

    private const DEFAULT_TARGETS = ['.claude/skills', '.agents/skills'];

    private const AGENTS_MD_START = '<!-- vondry/bolt-skills:start (managed by composer, do not edit) -->';
    private const AGENTS_MD_END = '<!-- vondry/bolt-skills:end -->';

    private const GITIGNORE_START = '# >>> vondry/bolt-skills (managed by composer, do not edit)';
    private const GITIGNORE_END = '# <<< vondry/bolt-skills';

    private Composer $composer;

    private IOInterface $io;

    private Filesystem $filesystem;

    public static function getSubscribedEvents(): array
    {
        return [
            ScriptEvents::POST_INSTALL_CMD => 'install',
            ScriptEvents::POST_UPDATE_CMD => 'install',
        ];
    }

    public function activate(Composer $composer, IOInterface $io): void
    {
        $this->composer = $composer;
        $this->io = $io;
        $this->filesystem = new Filesystem();
    }

    public function deactivate(Composer $composer, IOInterface $io): void
    {
    }

    public function uninstall(Composer $composer, IOInterface $io): void
    {
        $this->activate($composer, $io);

        $projectDir = $this->getProjectDir();
        $removed = 0;

        foreach ($this->getTargets() as $target) {
            $removed += $this->removeLinks($projectDir . '/' . $target, []);
            $this->removeEmptyDirs($projectDir, $target);
        }

        $this->removeBlock($projectDir . '/.gitignore', self::GITIGNORE_START, self::GITIGNORE_END);
        $this->removeBlock($projectDir . '/AGENTS.md', self::AGENTS_MD_START, self::AGENTS_MD_END);

        $this->io->write(sprintf('<info>bolt-skills:</info> removed %d skill link(s) and managed blocks', $removed));
    }

    public function install(): void
    {
        $packageDir = $this->getPackageDir();
        if ($packageDir === null) {
            return;
        }

        $projectDir = $this->getProjectDir();
        $skills = $this->findSkills($packageDir . '/skills');
        $linked = [];

        foreach ($this->getTargets() as $target) {
            $targetDir = $projectDir . '/' . $target;
            $this->filesystem->ensureDirectoryExists($targetDir);

            // Drop links to skills that no longer exist in the installed version.
            $this->removeLinks($targetDir, $skills);

            foreach ($skills as $skill) {
                if ($this->linkSkill($packageDir . '/skills/' . $skill, $targetDir . '/' . $skill)) {
                    $linked[] = '/' . $target . '/' . $skill;
                }
            }
        }

        if ($this->getOption('gitignore', true)) {
            $this->writeBlock($projectDir . '/.gitignore', self::GITIGNORE_START, self::GITIGNORE_END, implode("\n", $linked));
        }

        if ($this->getOption('agents-md', true)) {
            $this->writeBlock(
                $projectDir . '/AGENTS.md',
                self::AGENTS_MD_START,
                self::AGENTS_MD_END,
                $this->renderAgentsMd($projectDir, $packageDir, $skills),
            );
        }

        $this->io->write(sprintf(
            '<info>bolt-skills:</info> linked %d skill(s) into %s',
            count($skills),
            implode(', ', $this->getTargets()),
        ));
    }

    /**
     * @return list<string>
     */
    private function findSkills(string $skillsDir): array
    {
        $skills = [];
        foreach (glob($skillsDir . '/*/SKILL.md') ?: [] as $file) {
            $skills[] = basename(dirname($file));
        }
        sort($skills);

        return $skills;
    }

    private function linkSkill(string $source, string $link): bool
    {
        if (is_link($link) || $this->filesystem->isJunction($link)) {
            if ($this->isOwnLink($link) && realpath($link) === realpath($source)) {
                return true;
            }
            if (! $this->isOwnLink($link)) {
                $this->io->writeError(sprintf('<warning>bolt-skills: %s links elsewhere, skipped</warning>', $link));

                return false;
            }
            $this->unlink($link);
        } elseif (file_exists($link)) {
            $this->io->writeError(sprintf('<warning>bolt-skills: %s already exists and is not a link, skipped</warning>', $link));

            return false;
        }

        if ($this->filesystem->relativeSymlink($source, $link)) {
            return true;
        }

        // Windows without symlink privileges: fall back to a directory junction.
        if (Platform::isWindows()) {
            $this->filesystem->junction($source, $link);

            return true;
        }

        $this->io->writeError(sprintf('<warning>bolt-skills: could not symlink %s</warning>', $link));

        return false;
    }

    /**
     * Removes links in $dir that point into this package, except those named in $keep.
     *
     * @param list<string> $keep
     */
    private function removeLinks(string $dir, array $keep): int
    {
        $removed = 0;
        // scandir() rather than glob(): glob() skips dangling links, which are exactly the stale ones.
        foreach (is_dir($dir) ? (scandir($dir) ?: []) : [] as $name) {
            $entry = $dir . '/' . $name;
            if ($name === '.' || $name === '..' || in_array($name, $keep, true) || ! $this->isOwnLink($entry)) {
                continue;
            }
            $this->unlink($entry);
            ++$removed;
        }

        return $removed;
    }

    private function isOwnLink(string $path): bool
    {
        if (! is_link($path) && ! $this->filesystem->isJunction($path)) {
            return false;
        }
        $target = readlink($path);
        if ($target === false) {
            return false;
        }
        $target = str_replace('\\', '/', $target);

        return str_contains($target, self::PACKAGE_NAME . '/skills/');
    }

    private function unlink(string $path): void
    {
        if ($this->filesystem->isJunction($path)) {
            $this->filesystem->removeJunction($path);

            return;
        }
        $this->filesystem->unlink($path);
    }

    /**
     * Removes $relativeDir and its parents up to the project root, as long as they are empty.
     */
    private function removeEmptyDirs(string $projectDir, string $relativeDir): void
    {
        $parts = explode('/', trim($relativeDir, '/'));
        while ($parts !== []) {
            $dir = $projectDir . '/' . implode('/', $parts);
            if (! is_dir($dir) || is_link($dir) || ! $this->filesystem->isDirEmpty($dir)) {
                return;
            }
            rmdir($dir);
            array_pop($parts);
        }
    }

    /**
     * Inserts or replaces the managed block; creates the file if needed.
     */
    private function writeBlock(string $file, string $start, string $end, string $body): void
    {
        $block = $start . "\n" . ($body === '' ? '' : $body . "\n") . $end;
        $content = is_file($file) ? (string) file_get_contents($file) : '';
        $pattern = $this->blockPattern($start, $end, false);

        if (preg_match($pattern, $content) === 1) {
            $updated = (string) preg_replace_callback($pattern, static fn (): string => $block, $content, 1);
        } else {
            $updated = rtrim($content) === '' ? $block . "\n" : rtrim($content) . "\n\n" . $block . "\n";
        }

        if ($updated !== $content) {
            file_put_contents($file, $updated);
        }
    }

    /**
     * Removes the managed block; deletes the file when nothing else is left in it.
     */
    private function removeBlock(string $file, string $start, string $end): void
    {
        if (! is_file($file)) {
            return;
        }
        $content = (string) file_get_contents($file);
        $updated = (string) preg_replace($this->blockPattern($start, $end, true), '', $content);
        if ($updated === $content) {
            return;
        }

        $updated = rtrim((string) preg_replace("/\n{3,}/", "\n\n", $updated));
        if ($updated === '') {
            unlink($file);

            return;
        }
        file_put_contents($file, $updated . "\n");
    }

    private function blockPattern(string $start, string $end, bool $withSurroundingNewlines): string
    {
        $block = preg_quote($start, '/') . '.*?' . preg_quote($end, '/');

        return '/' . ($withSurroundingNewlines ? '\n*' . $block . '\n?' : $block) . '/s';
    }

    /**
     * @param list<string> $skills
     */
    private function renderAgentsMd(string $projectDir, string $packageDir, array $skills): string
    {
        $packagePath = str_starts_with($packageDir, $projectDir . '/')
            ? substr($packageDir, strlen($projectDir) + 1)
            : $packageDir;
        $targets = implode('`, `', array_map(static fn (string $t): string => $t . '/', $this->getTargets()));

        $lines = [
            '## Bolt CMS Agent Skills',
            '',
            sprintf('Installed by `%s`. Skills are symlinked into `%s` and refreshed on `composer install` / `composer update`.', self::PACKAGE_NAME, $targets),
            sprintf('For building or auditing a complete site, follow [`%1$s/WORKFLOWS.md`](%1$s/WORKFLOWS.md).', $packagePath),
            '',
        ];
        foreach ($skills as $skill) {
            $lines[] = sprintf('- [`%2$s`](%1$s/skills/%2$s/SKILL.md)', $packagePath, $skill);
        }

        return implode("\n", $lines);
    }

    private function getPackageDir(): ?string
    {
        $package = $this->composer->getRepositoryManager()->getLocalRepository()->findPackage(self::PACKAGE_NAME, '*');
        if ($package === null) {
            return null;
        }
        $path = $this->composer->getInstallationManager()->getInstallPath($package);

        return $path === null ? null : rtrim(str_replace('\\', '/', $path), '/');
    }

    private function getProjectDir(): string
    {
        $composerFile = $this->composer->getConfig()->getConfigSource()->getName();
        $dir = realpath(dirname($composerFile));

        return str_replace('\\', '/', $dir === false ? (string) getcwd() : $dir);
    }

    /**
     * @return list<string>
     */
    private function getTargets(): array
    {
        $targets = $this->getOption('targets', self::DEFAULT_TARGETS);
        if (! is_array($targets)) {
            return self::DEFAULT_TARGETS;
        }

        return array_values(array_filter(array_map(
            static fn (mixed $t): string => trim(str_replace('\\', '/', (string) $t), '/'),
            $targets,
        ), static fn (string $t): bool => $t !== '' && ! str_contains($t, '..')));
    }

    private function getOption(string $key, mixed $default): mixed
    {
        $extra = $this->composer->getPackage()->getExtra();

        return $extra['bolt-skills'][$key] ?? $default;
    }
}
