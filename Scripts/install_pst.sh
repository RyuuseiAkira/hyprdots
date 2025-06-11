#!/usr/bin/env bash
#|---/ /+--------------------------------------+---/ /|#
#|--/ /-| Script to apply post install configs |--/ /-|#
#|-/ /--| Prasanth Rangan                      |-/ /--|#
#|/ /---+--------------------------------------+/ /---|#

# Define colors for cleaner output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

scrDir=$(dirname "$(realpath "$0")")
source "${scrDir}/global_fn.sh"
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Unable to source global_fn.sh..."
    exit 1
fi

# chezmoi
if ! pkg_installed chezmoi; then
    echo -e "${YELLOW}[WARN]${NC} chezmoi is not installed."
    if pkg_installed yay; then
        echo -e "${GREEN}[INFO]${NC} yay detected. Attempting to install chezmoi..."
        yay -S --noconfirm chezmoi
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[INFO]${NC} chezmoi installed successfully."
        else
            echo -e "${RED}[ERROR]${NC} Failed to install chezmoi with yay. Please install it manually."
            echo -e "${YELLOW}[SKIP]${NC} Skipping dotfile application."
        fi
    else
        echo -e "${RED}[ERROR]${NC} yay is not installed. Cannot automatically install chezmoi."
        echo -e "${YELLOW}[SKIP]${NC} Skipping dotfile application. Please install chezmoi and yay manually."
    fi
fi

# Proceed with chezmoi if it's installed now
if pkg_installed chezmoi; then
    echo -e "${GREEN}[INFO]${NC} chezmoi detected. Initializing dotfiles..."
    chezmoi init --apply https://github.com/RyuuseiAkira/dotfiles
    echo -e "${GREEN}[INFO]${NC} Dotfiles applied using chezmoi."
fi

# ---

## Install mdrop

# Check if cargo is installed, as it's needed to build mdrop
if ! pkg_installed cargo; then
    echo -e "${RED}[ERROR]${NC} cargo is not installed. Cannot build mdrop. Please install rustup/cargo first."
else
    # Set default Rust toolchain to stable before building Rust projects
    echo -e "${GREEN}[INFO]${NC} Setting Rust default toolchain to stable (via rustup)..."
    rustup default stable
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}[WARN]${NC} Failed to set Rust default toolchain to stable. This might indicate 'rustup' is not installed or configured correctly. Continuing anyway, but build might fail if toolchain is incorrect."
    fi

    echo -e "${GREEN}[INFO]${NC} Installing mdrop..."
    mdrop_dir="${scrDir}/mdrop" # Define a directory for cloning mdrop

    if [ -d "${mdrop_dir}" ]; then
        echo -e "${YELLOW}[WARN]${NC} mdrop directory already exists, pulling latest changes..."
        git -C "${mdrop_dir}" pull
    else
        echo -e "${GREEN}[INFO]${NC} Cloning mdrop repository..."
        git clone https://github.com/frahz/mdrop.git "${mdrop_dir}"
    fi

    if [ -d "${mdrop_dir}" ]; then
        echo -e "${GREEN}[INFO]${NC} Building mdrop..."
        (cd "${mdrop_dir}" && cargo build --release)

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[INFO]${NC} mdrop built successfully. Moving to /usr/local/bin/..."
            sudo mv "${mdrop_dir}/target/release/mdrop" /usr/local/bin/
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[INFO]${NC} mdrop moved to /usr/local/bin/."

                echo -e "${GREEN}[INFO]${NC} Setting up udev rules for mdrop..."
                udev_rules_file_mdrop="/etc/udev/rules.d/99-mdrop.rules"
                udev_rule_mdrop='SUBSYSTEM=="usb", ATTRS{idVendor}=="2fc6", MODE="0666"'

                if grep -q "${udev_rule_mdrop}" "${udev_rules_file_mdrop}" 2>/dev/null; then
                    echo -e "${YELLOW}[WARN]${NC} udev rule already exists for mdrop."
                else
                    echo "${udev_rule_mdrop}" | sudo tee "${udev_rules_file_mdrop}" > /dev/null
                    echo -e "${GREEN}[INFO]${NC} udev rule added to ${udev_rules_file_mdrop}."
                fi
                # Udev reload is done once after all relevant rules are set
            else
                echo -e "${RED}[ERROR]${NC} Failed to move mdrop binary to /usr/local/bin/."
            fi
        else
            echo -e "${RED}[ERROR]${NC} Failed to build mdrop. Check cargo output for details."
        CITE: 
        fi
        # Clean up the mdrop repository after installation attempt
        echo -e "${GREEN}[INFO]${NC} Cleaning up mdrop repository..."
        rm -rf "${mdrop_dir}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to clone mdrop repository."
    fi
fi # End of cargo check block for mdrop

# ---

## Install msi-ec (Kernel Module)

echo -e "${GREEN}[INFO]${NC} Installing msi-ec (kernel module)..."
msi_ec_dir="${scrDir}/msi-ec" # Define a directory for cloning msi-ec

# Dynamically determine kernel headers package
KERNEL_NAME=$(uname -r)
KERNEL_HEADERS_PKG="linux-headers" # Default for standard kernel

if echo "$KERNEL_NAME" | grep -q -- "-zen"; then
    KERNEL_HEADERS_PKG="linux-zen-headers"
elif echo "$KERNEL_NAME" | grep -q -- "-lts"; then
    KERNEL_HEADERS_PKG="linux-lts-headers"
# Add more specific flavors if needed, e.g., elif echo "$KERNEL_NAME" | grep -q -- "-hardened"; then KERNEL_HEADERS_PKG="linux-hardened-headers"
fi

# Install prerequisites for kernel modules on Arch
echo -e "${GREEN}[INFO]${NC} Installing prerequisites for msi-ec (base-devel, ${KERNEL_HEADERS_PKG})..."
sudo pacman -S --noconfirm --needed base-devel "${KERNEL_HEADERS_PKG}"
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Failed to install msi-ec build prerequisites. Skipping msi-ec installation."
else
    # Check if dkms is installed, install if not
    if ! pkg_installed dkms; then
        echo -e "${YELLOW}[WARN]${NC} dkms is not installed. Attempting to install dkms with yay..."
        if pkg_installed yay; then
            yay -S --noconfirm dkms
            if [ $? -ne 0 ]; then
                echo -e "${RED}[ERROR]${NC} Failed to install dkms with yay. Skipping msi-ec installation."
                dkms_installed=false
            else
                echo -e "${GREEN}[INFO]${NC} dkms installed successfully."
                dkms_installed=true
            fi
        else
            echo -e "${RED}[ERROR]${NC} yay is not installed. Cannot automatically install dkms. Skipping msi-ec installation."
            dkms_installed=false
        fi
    else
        echo -e "${GREEN}[INFO]${NC} dkms detected."
        dkms_installed=true
    fi

    if [ "$dkms_installed" = true ]; then
        if [ -d "${msi_ec_dir}" ]; then
            echo -e "${YELLOW}[WARN]${NC} msi-ec directory already exists, pulling latest changes..."
            git -C "${msi_ec_dir}" pull
        else
            echo -e "${GREEN}[INFO]${NC} Cloning msi-ec repository..."
            git clone https://github.com/BeardOverflow/msi-ec.git "${msi_ec_dir}"
        fi

        if [ -d "${msi_ec_dir}" ]; then
            echo -e "${GREEN}[INFO]${NC} Building and installing msi-ec kernel module using DKMS..."
            (cd "${msi_ec_dir}" && sudo make dkms-install)

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[INFO]${NC} msi-ec kernel module installed successfully via DKMS."
                # As per user request, skipping the explicit udev rule copy for msi-ec.
                # If needed, the user should manually copy the udev rule as per msi-ec's README.
            else
                echo -e "${RED}[ERROR]${NC} Failed to install msi-ec kernel module via DKMS. Check make output for details."
            fi
            # Clean up the msi-ec repository after installation attempt
            echo -e "${GREEN}[INFO]${NC} Cleaning up msi-ec repository..."
            rm -rf "${msi_ec_dir}"
        else
            echo -e "${RED}[ERROR]${NC} Failed to clone msi-ec repository."
        fi
    fi
fi # End of msi-ec installation attempts

# ---

## Install custom package: agsv1

echo -e "${GREEN}[INFO]${NC} Installing custom package: agsv1..."

# Check if agsv1 is already installed
if pkg_installed agsv1; then
    echo -e "${YELLOW}[SKIP]${NC} agsv1 is already installed. Skipping custom package build."
else
    agsv1_build_dir="${scrDir}/agsv1-build" # Temporary directory for building agsv1
    mkdir -p "${agsv1_build_dir}"

    if [ ! -d "${agsv1_build_dir}" ]; then
        echo -e "${RED}[ERROR]${NC} Failed to create directory ${agsv1_build_dir}. Cannot build agsv1."
    else
        # --- Install and Downgrade TypeScript if necessary ---
        REQUIRED_TS_VER="5.1.6-1"
        CURRENT_TS_VER=$(pacman -Q typescript 2>/dev/null | awk '{print $2}')

        if [ "$CURRENT_TS_VER" != "$REQUIRED_TS_VER" ]; then
            echo -e "${GREEN}[INFO]${NC} Ensuring typescript version ${REQUIRED_TS_VER} is installed for agsv1 build using 'downgrade' utility..."

            # First, ensure 'downgrade' is installed
            if ! pkg_installed downgrade; then
                echo -e "${YELLOW}[WARN]${NC} 'downgrade' utility not found. Attempting to install it via yay..."
                if pkg_installed yay; then
                    yay -S --noconfirm downgrade
                    if [ $? -ne 0 ]; then
                        echo -e "${RED}[ERROR]${NC} Failed to install 'downgrade' utility. Cannot guarantee specific typescript version. Aborting agsv1 installation."
                        rm -rf "${agsv1_build_dir}"
                        exit 1
                    fi
                else
                    echo -e "${RED}[ERROR]${NC} yay is not installed. Cannot automatically install 'downgrade'. Please install 'downgrade' manually from AUR. Aborting agsv1 installation."
                    rm -rf "${agsv1_build_dir}"
                    exit 1
                fi
            fi

            echo -e "${GREEN}[INFO]${NC} Running 'sudo downgrade typescript'. Please select version ${REQUIRED_TS_VER} and confirm adding to IgnorePkg."
            # The 'downgrade' command is interactive, requiring user input.
            # It will list versions and ask for selection and IgnorePkg confirmation.
            sudo downgrade typescript=5.1.6-1
            if [ $? -ne 0 ]; then
                echo -e "${RED}[ERROR]${NC} 'downgrade typescript' failed or was cancelled. Aborting agsv1 installation."
                rm -rf "${agsv1_build_dir}"
                exit 1
            fi
            echo -e "${GREEN}[INFO]${NC} typescript ${REQUIRED_TS_VER} should now be installed and ignored by pacman."
        else
            echo -e "${GREEN}[INFO]${NC} Correct typescript version (${REQUIRED_TS_VER}) already installed. Verifying it's ignored..."
            # Manually ensure IgnorePkg is set, in case downgrade was skipped or didn't add it
            PACMAN_CONF_PATH="/etc/pacman.conf"
            PKG_TO_IGNORE="typescript"

            if grep -qE "^IgnorePkg =.*\\b${PKG_TO_IGNORE}\\b" "$PACMAN_CONF_PATH"; then
                echo -e "${GREEN}[INFO]${NC} 'typescript' is correctly in pacman's IgnorePkg list."
            elif grep -q "^#IgnorePkg =" "$PACMAN_CONF_PATH"; then
                sudo sed -i "s/^#IgnorePkg =.*/IgnorePkg = ${PKG_TO_IGNORE}/" "$PACMAN_CONF_PATH"
                echo -e "${GREEN}[INFO]${NC} Uncommented and added 'typescript' to pacman's IgnorePkg list."
            elif grep -q "^IgnorePkg =" "$PACMAN_CONF_PATH"; then
                sudo sed -i "/^IgnorePkg =/ s/$/ ${PKG_TO_IGNORE}/" "$PACMAN_CONF_PATH"
                echo -e "${GREEN}[INFO]${NC} Added 'typescript' to existing pacman's IgnorePkg list."
            else
                sudo sed -i "/^\[options\]/a IgnorePkg = ${PKG_TO_IGNORE}" "$PACMAN_CONF_PATH"
                echo -e "${GREEN}[INFO]${NC} Added 'IgnorePkg = typescript' to pacman.conf."
            fi
        fi
        # --- End TypeScript Version Handling ---

        echo -e "${GREEN}[INFO]${NC} Creating PKGBUILD for agsv1 in ${agsv1_build_dir}..."
        cat <<EOF > "${agsv1_build_dir}/PKGBUILD"
# Maintainer: kotontrion <kotontrion@tutanota.de>

# This package is only intended to be used while migrating from ags v1.8.2 to ags v2.0.0.
# Many ags configs are quite big and it takes a while to migrate, therefore I made this package
# to install ags v1.8.2 as "agsv1", so both versions can be installed at the same time, making it
# possible to migrate bit by bit while still having a working v1 config around.
#
# First update the aylurs-gtk-shell package to v2, then install this one.
#
# This package won't receive any updates anymore, so as soon as you migrated, uninstall this one.

pkgname=agsv1
_pkgname=ags
pkgver=1.9.0
pkgrel=1
pkgdesc="Aylurs's Gtk Shell (AGS), An eww inspired gtk widget system."
arch=('x86_64')
url="https://github.com/Aylur/ags"
license=('GPL-3.0-only')
makedepends=('git' 'gobject-introspection' 'meson' 'glib2-devel' 'npm' 'typescript')
depends=('gjs' 'glib2' 'glibc' 'gtk3' 'gtk-layer-shell' 'libpulse' 'pam')
optdepends=('gnome-bluetooth-3.0: required for bluetooth service'
            'greetd: required for greetd service'
            'libdbusmenu-gtk3: required for systemtray service'
            'libsoup3: required for the Utils.fetch feature'
            'libnotify: required for sending notifications'
            'networkmanager: required for network service'
            'power-profiles-daemon: required for powerprofiles service'
            'upower: required for battery service')
backup=('etc/pam.d/ags')
source=("\$pkgname-\$pkgver.tar.gz::https://github.com/Aylur/ags/archive/refs/tags/v\${pkgver}.tar.gz"
        "git+https://gitlab.gnome.org/GNOME/libgnome-volume-control")
sha256sums=('962f99dcf202eef30e978d1daedc7cdf213e07a3b52413c1fb7b54abc7bd08e6'
            SKIP)

prepare() {
    cd "\$srcdir/\$_pkgname-\$pkgver"
    mv -T "\$srcdir"/libgnome-volume-control subprojects/gvc
}

build() {
    cd "\$srcdir/\$_pkgname-\$pkgver"
    npm install
    arch-meson build --libdir "lib/\$_pkgname" -Dbuild_types=true
    meson compile -C build
}

package() {
    cd "\$srcdir/\$_pkgname-\$pkgver"
    meson install -C build --destdir "\$pkgdir"
    rm \${pkgdir}/usr/bin/ags
    ln -sf /usr/share/com.github.Aylur.ags/com.github.Aylur.ags \${pkgdir}/usr/bin/agsv1
}
EOF
        echo -e "${GREEN}[INFO]${NC} PKGBUILD created successfully."

        echo -e "${GREEN}[INFO]${NC} Building and installing agsv1 using makepkg..."
        (cd "${agsv1_build_dir}" && makepkg -si --noconfirm)

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[INFO]${NC} agsv1 installed successfully."
        else
            echo -e "${RED}[ERROR]${NC} Failed to build and install agsv1. Check makepkg output for details."
        fi

        # Clean up the build directory
        echo -e "${GREEN}[INFO]${NC} Cleaning up agsv1 build directory..."
        rm -rf "${agsv1_build_dir}"
    fi
fi

# ---

## Reload Udev Rules (for mdrop and any other changes)
# This step is done once after all relevant device-related udev rules are placed
echo -e "${GREEN}[INFO]${NC} Reloading udev rules (for mdrop and other system changes)..."
sudo udevadm control --reload-rules
echo -e "${GREEN}[INFO]${NC} All relevant udev rules applied and reloaded."

# ---

## SDDM Configuration

# sddm
if pkg_installed sddm; then
    echo -e "${GREEN}[INFO]${NC} [DISPLAYMANAGER] detected // sddm"
    if [ ! -d /etc/sddm.conf.d ]; then
        sudo mkdir -p /etc/sddm.conf.d
    fi

    if [ ! -f /etc/sddm.conf.d/kde_settings.t2.bkp ]; then
        echo -e "${GREEN}[INFO]${NC} [DISPLAYMANAGER] Configuring sddm..."
        echo -e "Select sddm theme:\n[1] Candy\n[2] Corners"
        read -p " :: Enter option number : " sddmopt

        case $sddmopt in
        1) sddmtheme="Candy" ;;
        *) sddmtheme="Corners" ;;
        esac

        sudo tar -xzf "${cloneDir}/Source/arcs/Sddm_${sddmtheme}.tar.gz" -C /usr/share/sddm/themes/
        sudo touch /etc/sddm.conf.d/kde_settings.conf
        sudo cp /etc/sddm.conf.d/kde_settings.conf /etc/sddm.conf.d/kde_settings.t2.bkp
        sudo cp "/usr/share/sddm/themes/${sddmtheme}/kde_settings.conf" /etc/sddm.conf.d/
    else
        echo -e "${YELLOW}[SKIP]${NC} sddm is already configured."
    fi

    if [ ! -f /usr/share/sddm/faces/${USER}.face.icon ] && [ -f "${cloneDir}/Source/misc/${USER}.face.icon" ]; then
        sudo cp "${cloneDir}/Source/misc/${USER}.face.icon" /usr/share/sddm/faces/
        echo -e "${GREEN}[INFO]${NC} [DISPLAYMANAGER] Avatar set for ${USER}."
    fi

else
    echo -e "${YELLOW}[WARN]${NC} sddm is not installed."
fi

# ---

## Dolphin File Manager

# dolphin
if pkg_installed dolphin && pkg_installed xdg-utils; then

    echo -e "${GREEN}[INFO]${NC} [FILEMANAGER] detected // dolphin"
    xdg-mime default org.kde.dolphin.desktop inode/directory
    echo -e "${GREEN}[INFO]${NC} [FILEMANAGER] Setting `xdg-mime query default "inode/directory"` as default file explorer."

else
    echo -e "${YELLOW}[WARN]${NC} dolphin is not installed."
fi

# ---

## Shell Configuration

# shell
"${scrDir}/restore_shl.sh"

# ---

## Flatpak Applications

# flatpak
if ! pkg_installed flatpak; then

    echo -e "${GREEN}[INFO]${NC} [FLATPAK] flatpak application list:"
    awk -F '#' '$1 != "" {print "["++count"]", $1}' "${scrDir}/.extra/custom_flat.lst"
    prompt_timer 60 "Install these flatpaks? [Y/n]"
    fpkopt=${promptIn,,}

    if [ "${fpkopt}" = "y" ]; then
        echo -e "${GREEN}[INFO]${NC} [FLATPAK] Installing flatpaks..."
        "${scrDir}/.extra/install_fpk.sh"
    else
        echo -e "${YELLOW}[SKIP]${NC} Skipping flatpak installation."
    fi

else
    echo -e "${YELLOW}[SKIP]${NC} flatpak is already installed."
fi
