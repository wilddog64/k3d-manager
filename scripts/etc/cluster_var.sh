export IP=$(ip -4 route get 8.8.8.8 | perl -nle 'print $1 if /src (.*) uid/')
