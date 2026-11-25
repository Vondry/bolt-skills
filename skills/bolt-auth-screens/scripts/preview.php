<?php

declare(strict_types=1);

/*
 * bolt-auth-screens preview: renders every screen and state through Bolt's own controllers and
 * form types, with dummy forms — no user account, no reset token, no e-mail, no database write.
 *
 * Preview server (run from the project root):
 *   php -S 127.0.0.1:8899 -t public vendor/tomvondracek/bolt-skills/skills/bolt-auth-screens/scripts/preview.php
 *   → http://127.0.0.1:8899/__bolt-auth/   (every state side by side, desktop and 390 px)
 *   Every other URL is served from public/ (theme fonts, logo, script).
 *
 * Check (verify.sh):
 *   php preview.php check <project-root>
 *   Renders every state and prints PASS / FAIL lines.
 *
 * One state as HTML:
 *   php preview.php html <state> <project-root>
 */

use Bolt\Controller\Backend\AuthenticationController;
use Bolt\Form\ChangePasswordFormType;
use Bolt\Form\LoginType;
use Bolt\Form\ResetPasswordRequestFormType;
use Symfony\Component\Dotenv\Dotenv;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Session\Session;
use Symfony\Component\HttpFoundation\Session\Storage\MockArraySessionStorage;
use Symfony\Component\Security\Core\Exception\BadCredentialsException;
use Symfony\Component\Security\Core\Exception\TooManyLoginAttemptsAuthenticationException;

const STATES = [
    'login' => 'Login',
    'login-error' => 'Login · wrong credentials',
    'login-reset' => 'Login · after a password reset',
    'login-throttled' => 'Login · too many attempts',
    'reset-request' => 'Reset request',
    'reset-request-error' => 'Reset request · expired link',
    'reset-request-limited' => 'Reset request · rate limit',
    'check-email' => 'Reset request · link sent',
    'reset' => 'New password',
    'reset-mismatch' => 'New password · passwords differ',
    'reset-short' => 'New password · too short',
    'reset-weak' => 'New password · weak (password policy)',
];

// Deprecation notices of the project's vendor code are not this preview's business.
error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);

if (PHP_SAPI === 'cli-server') {
    $path = rawurldecode((string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH));
    if (! str_starts_with($path, '/__bolt-auth')) {
        if ($path !== '/' && is_file($_SERVER['DOCUMENT_ROOT'] . $path)) {
            return false;
        }
        http_response_code(404);
        echo 'Not found — this server only previews the sign-in screens: /__bolt-auth/';

        return true;
    }
    $state = trim(substr($path, strlen('/__bolt-auth')), '/');
    chdir(dirname($_SERVER['DOCUMENT_ROOT']));
    header('Content-Type: text/html; charset=utf-8');
    if ($state === '') {
        echo overview();
    } elseif (isset(STATES[$state])) {
        echo render($state);
    } else {
        http_response_code(404);
        echo 'Unknown state';
    }

    return true;
}

if (($argv[1] ?? '') === 'html' && isset(STATES[$argv[2] ?? ''])) {
    chdir($argv[3] ?? getcwd());
    echo render($argv[2]);
    exit(0);
}
if (($argv[1] ?? '') !== 'check') {
    fwrite(STDERR, "Usage: php -S 127.0.0.1:8899 -t public preview.php   or   php preview.php check|html <state> <project-root>\n");
    exit(2);
}
chdir($argv[2] ?? getcwd());
foreach (array_keys(STATES) as $state) {
    try {
        $html = render($state);
    } catch (Throwable $e) {
        echo "FAIL $state does not render: " . get_class($e) . ': ' . strtok($e->getMessage(), "\n") . "\n";
        continue;
    }
    $expected = match ($state) {
        'login-error', 'login-throttled', 'reset-request-error', 'reset-request-limited' => 'ba-alert is-danger',
        'login-reset', 'check-email' => 'ba-alert is-success',
        'reset-mismatch', 'reset-short', 'reset-weak' => 'ba-help is-error',
        default => 'class="ba-form"',
    };
    $marked = match ($state) {
        'reset-mismatch' => preg_match('/id="change_password_form_plainPassword_second"[^>]*is-invalid|is-invalid[^>]*id="change_password_form_plainPassword_second"/', $html) === 1,
        'reset-short', 'reset-weak' => preg_match('/id="change_password_form_plainPassword_first"[^>]*is-invalid|is-invalid[^>]*id="change_password_form_plainPassword_first"/', $html) === 1,
        default => true,
    };
    // Bolt's password fields: login[password] and change_password_form[plainPassword][first|second].
    preg_match_all('/<input[^>]*name="[^"]*(?:\[password\]|\[plainPassword\]\[[a-z]+\])"[^>]*>/', $html, $inputs);
    $exposed = array_filter($inputs[0], static fn (string $input): bool => ! str_contains($input, 'type="password"') || preg_match('/\svalue="[^"]/', $input) === 1);
    if ($exposed !== []) {
        echo "FAIL $state renders a password field as text or with a value: " . reset($exposed) . "\n";
        continue;
    }
    if (! str_contains($html, 'class="ba-screen"') || ! str_contains($html, $expected) || ! $marked) {
        echo "FAIL $state renders without " . (! $marked ? 'the field at fault marked' : $expected) . "\n";
    } else {
        echo 'PASS ' . STATES[$state] . "\n";
    }
}
exit(0);

function overview(): string
{
    $frames = '';
    foreach (STATES as $state => $label) {
        $frames .= '<figure><figcaption>' . htmlspecialchars($label) . '</figcaption><div class="row">'
            . '<iframe src="/__bolt-auth/' . $state . '" class="desktop" title="' . htmlspecialchars($label) . ' (desktop)"></iframe>'
            . '<iframe src="/__bolt-auth/' . $state . '" class="mobile" title="' . htmlspecialchars($label) . ' (390 px)"></iframe>'
            . "</div></figure>\n";
    }

    return '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Bolt sign-in screens · preview</title><style>'
        . 'body{margin:0;padding:24px;background:#d6d3d1;font:14px/1.4 system-ui,sans-serif;color:#18181b}'
        . 'figure{margin:0 0 40px}figcaption{font-weight:600;margin-bottom:8px}.row{display:flex;gap:24px;align-items:flex-start}'
        . 'iframe{border:0;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.2)}.desktop{width:1280px;height:800px;zoom:.6}.mobile{width:390px;height:800px;zoom:.6}'
        . "</style></head><body>\n$frames</body></html>";
}

function render(string $state): string
{
    static $kernel = null;
    if ($kernel === null) {
        require_once 'vendor/autoload.php';
        (new Dotenv())->bootEnv(getcwd() . '/.env');
        // Debug, so the container and the templates are rebuilt when src/ or the theme changed:
        // the preview always shows the code as it is on disk.
        $kernel = new App\Kernel((string) ($_SERVER['APP_ENV'] ?? 'dev'), true);
        $kernel->boot();
    }
    $container = $kernel->getContainer();

    $backend = (string) $container->getParameter('bolt.backend_url');
    $request = Request::create('http://' . ($_SERVER['HTTP_HOST'] ?? 'localhost') . $backend . '/login');
    $session = new Session(new MockArraySessionStorage());
    $request->setSession($session);
    $stack = $container->get('request_stack');
    while ($stack->pop() !== null) {
    }
    $stack->push($request);
    $container->get('router')->getContext()->fromRequest($request);
    $translator = $container->get('translator');
    // Any TwigAwareController renders with the theme's template path and asset package; its
    // createForm() reaches the form factory, which the compiled container keeps private.
    $controller = $container->get(AuthenticationController::class);
    // Always the templates as they are on disk, never a compiled copy of an earlier version.
    (fn () => $this->container->get('twig')->enableAutoReload())->call($controller);
    $forms = new class($controller) {
        public function __construct(private readonly object $controller)
        {
        }

        public function create(string $type, mixed $data = null, array $options = []): Symfony\Component\Form\FormInterface
        {
            return (fn () => $this->createForm($type, $data, $options))->call($this->controller);
        }
    };

    $flash = static fn (string $type, string $message) => $session->getFlashBag()->add($type, $message);

    [$template, $parameters] = match ($state) {
        'login', 'login-error', 'login-reset', 'login-throttled' => (static function () use ($state, $forms, $flash, $translator): array {
            if ($state === 'login-reset') {
                $flash('reset_password_success', $translator->trans('reset_password.reset_successful'));
            }

            return ['bolt-auth/login.twig', [
                'loginForm' => $forms->create(LoginType::class),
                'error' => match ($state) {
                    'login-error' => new BadCredentialsException(),
                    'login-throttled' => new TooManyLoginAttemptsAuthenticationException(15),
                    default => null,
                },
            ]];
        })(),
        'reset-request', 'reset-request-error', 'reset-request-limited' => (static function () use ($state, $forms, $flash, $translator): array {
            if ($state === 'reset-request-error') {
                $flash('reset_password_error', sprintf($translator->trans('reset_password.problem_with_request'), $translator->trans('The link in your email is expired. Please try to reset your password again.')));
            }
            if ($state === 'reset-request-limited') {
                $flash('reset_password_error', $translator->trans('bolt_auth.too_many_requests', ['%minutes%' => 15]));
            }

            return ['bolt-auth/reset-request.twig', ['requestForm' => $forms->create(ResetPasswordRequestFormType::class)]];
        })(),
        'check-email' => ['bolt-auth/check-email.twig', ['tokenLifetime' => 3600]],
        default => (static function () use ($state, $forms): array {
            $form = $forms->create(ChangePasswordFormType::class, null, ['csrf_protection' => false]);
            if ($state === 'reset-mismatch') {
                $form->submit(['plainPassword' => ['first' => 'correct-horse', 'second' => 'correct-hors']]);
            } elseif ($state === 'reset-short') {
                $form->submit(['plainPassword' => ['first' => 'abc', 'second' => 'abc']]);
            } elseif ($state === 'reset-weak') {
                // Long enough for Bolt's own rule, refused by the policy of BoltAuthPasswordPolicyExtension.
                $form->submit(['plainPassword' => ['first' => 'heslo1234', 'second' => 'heslo1234']]);
            }

            return ['bolt-auth/reset.twig', ['resetForm' => $form]];
        })(),
    };

    return (string) $controller->render($template, $parameters)->getContent();
}
