<?php

declare(strict_types=1);

namespace App;

use Bolt\Form\ChangePasswordFormType;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\Form\AbstractTypeExtension;
use Symfony\Component\Form\Extension\Core\Type\RepeatedType;
use Symfony\Component\Form\FormBuilderInterface;
use Symfony\Component\Validator\Constraints\Length;
use Symfony\Component\Validator\Constraints\NotCompromisedPassword;
use Symfony\Component\Validator\Constraints\PasswordStrength;

/**
 * bolt-auth-screens: the password policy on Bolt's "set a new password" form.
 *
 * Bolt core validates that form with its own 6-character rule, so a forgotten password could be
 * replaced by a weaker one than the admin accepts (bolt-security-hardening, config/validator/user.yaml).
 * This adds the same rules to the new password: the minimum length, a medium PasswordStrength score
 * and NotCompromisedPassword (Have I Been Pwned; only 5 characters of the SHA-1 hash leave the
 * server; skipOnError keeps a reset possible on hosts that block outgoing HTTPS).
 *
 * Copied by scaffold.sh; shared by every project — change the skill, not the copy.
 */
final class BoltAuthPasswordPolicyExtension extends AbstractTypeExtension
{
    public function __construct(
        #[Autowire('%bolt_auth.password_min_length%')]
        private readonly int $minLength = 12,
    ) {
    }

    public static function getExtendedTypes(): iterable
    {
        return [ChangePasswordFormType::class];
    }

    /**
     * @param array<string, mixed> $options
     */
    public function buildForm(FormBuilderInterface $builder, array $options): void
    {
        if (! $builder->has('plainPassword')) {
            return;
        }

        $field = $builder->get('plainPassword');
        $first = $field->getOption('first_options', []);
        $first = is_array($first) ? $first : [];
        $constraints = $first['constraints'] ?? [];
        $first['constraints'] = [
            ...(is_array($constraints) ? $constraints : [$constraints]),
            new Length(min: $this->minLength, max: 4096),
            new PasswordStrength(minScore: PasswordStrength::STRENGTH_MEDIUM),
            new NotCompromisedPassword(skipOnError: true),
        ];
        $attr = $first['attr'] ?? [];
        $first['attr'] = [
            ...(is_array($attr) ? $attr : []),
            'minlength' => $this->minLength,
            'maxlength' => 4096,
            // Lets password managers generate a password that passes.
            'passwordrules' => sprintf('minlength: %d; required: lower; required: upper; required: digit;', $this->minLength),
        ];

        // Bolt's own options (type, labels, mismatch message, mapped: false) stay as they are.
        $builder->add('plainPassword', RepeatedType::class, [
            'type' => $field->getOption('type'),
            'first_options' => $first,
            'second_options' => $field->getOption('second_options', []),
            'invalid_message' => $field->getOption('invalid_message'),
            'mapped' => $field->getOption('mapped', false),
        ]);
    }
}
